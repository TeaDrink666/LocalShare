import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:common/api_route_builder.dart';
import 'package:common/isolate.dart';
import 'package:common/model/device.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/dto/info_register_dto.dart';
import 'package:common/model/dto/multicast_dto.dart';
import 'package:common/model/dto/prepare_upload_request_dto.dart';
import 'package:common/model/dto/prepare_upload_response_dto.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/file_type.dart';
import 'package:common/model/session_status.dart';
import 'package:common/util/sleep.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/features/backup/data/backup_profile_store.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest_codec.dart';
import 'package:localsend_app/features/backup/protocol/protocol.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/progress_page.dart';
import 'package:localsend_app/pages/send_page.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:rhttp/rhttp.dart';
import 'package:routerino/routerino.dart';
import 'package:uri_content/uri_content.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
final _logger = Logger('Send');

final class BackupNativeTransferResult {
  BackupNativeTransferResult({
    required Iterable<String> committedMediaKeys,
    required this.totalItemCount,
    required this.errorMessage,
  }) : committedMediaKeys = Set<String>.unmodifiable(committedMediaKeys);

  final Set<String> committedMediaKeys;
  final int totalItemCount;
  final String? errorMessage;

  int get remainingItemCount => totalItemCount - committedMediaKeys.length;
}

final class BackupProtocolUnavailableException implements Exception {
  const BackupProtocolUnavailableException();

  @override
  String toString() => 'The target does not support LocalShare backup receipts.';
}

/// This provider manages sending files to other devices.
///
/// In contrast to [serverProvider], this provider does not manage a server.
/// Instead, it only does HTTP requests to other servers.
final sendProvider = NotifierProvider<SendNotifier, Map<String, SendSessionState>>((ref) {
  return SendNotifier();
}, onChanged: (_, next, ref) => ref.notifier(taskProvider).syncSend(next));

class SendNotifier extends Notifier<Map<String, SendSessionState>> {
  SendNotifier();
  final _resumableSessions = <String>{};
  final _admissionSessions = <String>{};
  final _backupOwnedSessions = <String>{};
  final _jobs = <String, Completer<void>>{};
  final _backupJobs = <String, Completer<void>>{};
  final _retrying = <String>{};

  Future<void> _resetRemoteTask(Device target, String id, TransferTask? previous) async {
    if (previous == null) return;
    final info = ref.read(deviceFullInfoProvider);
    final remoteId = previous.retryData['remoteSessionId'] as String? ?? sha256.convert(utf8.encode('${info.fingerprint}:$id')).toString();
    try {
      await ref.read(httpProvider).discovery.post(ApiRoute.cancel.target(target, query: {'sessionId': remoteId, 'ifPaused': '1'}));
    } on Object {
      // A restarted receiver may have already closed its in-memory session.
    }
  }

  Future<void> retryStoredTask(String id) async {
    if (!_retrying.add(id)) return;
    try {
      await _retryStoredTask(id);
    } finally {
      _retrying.remove(id);
    }
  }

  Future<void> _retryStoredTask(String id) async {
    final manager = ref.notifier(taskProvider);
    final callback = manager.retries[id];
    if (callback != null) {
      await callback();
      return;
    }
    final task = manager.state.tasks[id];
    if (task == null || task.retryData['target'] == null) return;
    final target = DeviceMapper.fromJson(Map<String, dynamic>.from(task.retryData['target'] as Map));
    final sources = (task.retryData['sources'] as List).map((raw) {
      final file = Map<String, dynamic>.from(raw as Map);
      return CrossFile(
          name: file['name'] as String,
          fileType: FileType.values.byName(file['type'] as String),
          size: file['size'] as int,
          thumbnail: null,
          asset: null,
          path: file['path'] as String?,
          bytes: file['bytes'] == null ? null : base64Decode(file['bytes'] as String),
          lastModified: file['modified'] == null ? null : DateTime.parse(file['modified'] as String),
          lastAccessed: null);
    }).toList();
    if (task.retryData['manifest'] != null) {
      final manifest = const BackupManifestCodec().decode(task.retryData['manifest'] as String);
      final store = await BackupProfileStore.openDefault();
      try {
        await startBackupSession(
            target: target,
            files: sources,
            manifest: manifest,
            onCommitted: (keys) async {
              await store.confirmPending(manifest.profileId, mediaKeys: keys);
            });
      } finally {
        store.close();
      }
    } else {
      await startSession(
          target: target, files: sources, background: true, sessionIdOverride: id, fileIds: (task.retryData['fileIds'] as List).cast<String>());
    }
  }

  List<Map<String, dynamic>> _sourceData(List<CrossFile> files) => files
      .map((file) => <String, dynamic>{
            'name': file.name,
            'size': file.size,
            'type': file.fileType.name,
            'path': file.path,
            'bytes': file.path == null && file.bytes != null ? base64Encode(file.bytes!) : null,
            'modified': file.lastModified?.toIso8601String(),
          })
      .toList();

  Future<void> startSession(
      {required Device target,
      required List<CrossFile> files,
      required bool background,
      String? sessionIdOverride,
      List<String>? fileIds,
      BackupPrepareMetadata? backupMetadata,
      bool keepSessionOnSuccess = false}) async {
    final id = sessionIdOverride ?? _uuid.v4();
    while (_jobs[id] != null) {
      await _jobs[id]!.future;
    }
    final completion = Completer<void>();
    _jobs[id] = completion;
    try {
      await _startManagedSession(
          target: target,
          files: files,
          background: background,
          sessionIdOverride: id,
          fileIds: fileIds,
          backupMetadata: backupMetadata,
          keepSessionOnSuccess: keepSessionOnSuccess);
    } finally {
      _jobs.remove(id);
      completion.complete();
    }
  }

  Future<void> _startManagedSession(
      {required Device target,
      required List<CrossFile> files,
      required bool background,
      required String sessionIdOverride,
      List<String>? fileIds,
      BackupPrepareMetadata? backupMetadata,
      bool keepSessionOnSuccess = false}) async {
    final id = sessionIdOverride;
    final ids = fileIds ?? List.generate(files.length, (_) => _uuid.v4());
    final manager = ref.notifier(taskProvider);
    final existing = manager.state.tasks[id];
    await _resetRemoteTask(target, id, existing);
    _admissionSessions.remove(id);
    _resumableSessions.remove(id);
    manager.put(TransferTask(
        id: id,
        kind: backupMetadata == null ? TransferTaskKind.send : TransferTaskKind.backup,
        peer: target.alias,
        createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        stage: TransferTaskStage.queued,
        files: files.indexed
            .map((entry) => <String, dynamic>{'id': ids[entry.$1], 'name': entry.$2.name, 'size': entry.$2.size, 'status': 'queue'})
            .toList(),
        retryData: existing?.retryData ?? {'target': target.toJson(), 'sources': _sourceData(files), 'fileIds': ids}));
    if (!_backupOwnedSessions.contains(id)) {
      manager.retries[id] = () => startSession(
          target: target,
          files: files,
          background: true,
          sessionIdOverride: id,
          fileIds: ids,
          backupMetadata: backupMetadata,
          keepSessionOnSuccess: keepSessionOnSuccess);
    }
    manager.cancellations[id] = () => cancelSession(id);
    manager.pauses[id] = () => pauseSession(id);
    manager.disposals[id] = () => closeSession(id, clearSelection: false);
    if (!background) {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.tasks));
    }
    var busyRetries = 0;
    while (true) {
      if (!await manager.queue.acquire(id, media: backupMetadata != null)) {
        return;
      }
      if ({TransferTaskStage.canceled, TransferTaskStage.paused}.contains(manager.state.tasks[id]?.stage)) {
        manager.queue.release(id);
        return;
      }
      try {
        await _startSession(
            target: target,
            files: files,
            background: true,
            sessionIdOverride: id,
            fileIds: ids,
            backupMetadata: backupMetadata,
            keepSessionOnSuccess: true);
      } catch (error) {
        if (!{TransferTaskStage.paused, TransferTaskStage.canceled}.contains(manager.state.tasks[id]?.stage)) {
          manager.update(id, TransferTaskStage.failed, error: error.toString());
        }
        rethrow;
      } finally {
        if (!_backupOwnedSessions.contains(id)) manager.queue.release(id);
      }
      if (state[id]?.status != SessionStatus.recipientBusy || busyRetries++ >= 20) break;
      if ({TransferTaskStage.canceled, TransferTaskStage.paused}.contains(manager.state.tasks[id]?.stage)) break;
      manager.update(id, TransferTaskStage.queued, error: '等待接收端空闲');
      // Release admission during backoff so opposing transfers can progress.
      manager.queue.release(id);
      await Future<void>.delayed(Duration(milliseconds: 500 + DateTime.now().microsecond % 1500));
    }
    if (state[id]?.status == SessionStatus.recipientBusy &&
        manager.state.tasks[id]?.stage != TransferTaskStage.canceled &&
        manager.state.tasks[id]?.stage != TransferTaskStage.paused) {
      manager.update(id, TransferTaskStage.failed, error: '接收端一直繁忙，请稍后重试');
    }
  }

  void pauseSession(String id, {bool notifyPeer = true}) {
    ref.notifier(taskProvider).queue.release(id);
    final session = state[id];
    _prepareRequests.cancel(id);
    if (session != null) {
      _cancelRunningRequests(session);
      if (notifyPeer) {
        unawaited(ref
            .read(httpProvider)
            .discovery
            .post(ApiRoute.cancel.target(session.target, query: {
              'ifPaused': '1',
              'sessionId': session.remoteSessionId ?? sha256.convert(utf8.encode('${ref.read(deviceFullInfoProvider).fingerprint}:$id')).toString()
            }))
            .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      }
      state = state.updateSession(sessionId: id, state: (s) => s?.copyWith(status: SessionStatus.canceledBySender));
    }
  }

  final PrepareRequestCancelRegistry _prepareRequests = PrepareRequestCancelRegistry();

  @override
  Map<String, SendSessionState> init() {
    return {};
  }

  /// Sends a phone-media batch and returns only receiver-verified item IDs.
  ///
  /// The plan call first recovers any receipt whose previous response was
  /// lost. Missing files then use the normal LocalSend approval/upload flow,
  /// with namespaced backup metadata attached. A final commit query is the
  /// sole authority for advancing the Android backup ledger.
  Future<BackupNativeTransferResult> startBackupSession({
    required Device target,
    required List<CrossFile> files,
    required BackupManifest manifest,
    Future<void> Function(Set<String> keys)? onCommitted,
  }) async {
    while (_backupJobs[manifest.batchId] != null) {
      await _backupJobs[manifest.batchId]!.future;
    }
    final completion = Completer<void>();
    _backupJobs[manifest.batchId] = completion;
    try {
      return await _startManagedBackupSession(target: target, files: files, manifest: manifest, onCommitted: onCommitted);
    } finally {
      _backupJobs.remove(manifest.batchId);
      completion.complete();
    }
  }

  Future<BackupNativeTransferResult> _startManagedBackupSession({
    required Device target,
    required List<CrossFile> files,
    required BackupManifest manifest,
    Future<void> Function(Set<String> keys)? onCommitted,
  }) async {
    final id = manifest.batchId;
    final manager = ref.notifier(taskProvider);
    manager.put(TransferTask(
        id: id,
        kind: TransferTaskKind.backup,
        peer: target.alias,
        createdAt: manager.state.tasks[id]?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        stage: TransferTaskStage.queued,
        files: files.indexed
            .map((entry) => <String, dynamic>{
                  'id': 'media-${sha256.convert(utf8.encode(manifest.items.elementAt(entry.$1).snapshotItem.mediaKey))}',
                  'name': entry.$2.name,
                  'size': entry.$2.size,
                  'status': 'queue'
                })
            .toList(),
        retryData: {'target': target.toJson(), 'sources': _sourceData(files), 'manifest': const BackupManifestCodec().encode(manifest)}));
    manager.retries[id] = () async {
      await startBackupSession(target: target, files: files, manifest: manifest, onCommitted: onCommitted);
    };
    manager.cancellations[id] = () => cancelSession(id);
    manager.pauses[id] = () => pauseSession(id);
    if (!await manager.mediaJobs.acquire(id, media: true)) {
      throw StateError('备份任务已取消');
    }
    _backupOwnedSessions.add(id);
    try {
      final result = await _runBackupSession(target: target, files: files, manifest: manifest);
      if (manager.state.tasks[id]?.stage == TransferTaskStage.paused || manager.state.tasks[id]?.stage == TransferTaskStage.canceled) {
        return result;
      }
      manager.update(id, TransferTaskStage.verifying);
      await onCommitted?.call(result.committedMediaKeys);
      manager.update(id, result.remainingItemCount == 0 ? TransferTaskStage.completed : TransferTaskStage.failed, error: result.errorMessage);
      return result;
    } catch (error) {
      if (manager.state.tasks[id]?.stage != TransferTaskStage.paused && manager.state.tasks[id]?.stage != TransferTaskStage.canceled) {
        manager.update(id, TransferTaskStage.failed, error: error.toString());
      }
      rethrow;
    } finally {
      _backupOwnedSessions.remove(id);
      manager.queue.release(id);
      manager.mediaJobs.release(id);
    }
  }

  Future<BackupNativeTransferResult> _runBackupSession({
    required Device target,
    required List<CrossFile> files,
    required BackupManifest manifest,
  }) async {
    final bindings = _bindBackupFiles(files, manifest);
    final fileIds = List<String>.generate(
      bindings.length,
      (index) => 'media-${sha256.convert(utf8.encode(bindings[index].item.snapshotItem.mediaKey))}',
      growable: false,
    );
    final fullPrepareMetadata = BackupPrepareMetadata(
      manifest: manifest,
      targetFingerprint: target.fingerprint,
      fileIdToMediaKey: {
        for (var index = 0; index < bindings.length; index++) fileIds[index]: bindings[index].item.snapshotItem.mediaKey,
      },
    );

    final planResponse = await _postBackupPlan(
      target,
      BackupPlanRequest(metadata: fullPrepareMetadata),
    );
    if ({TransferTaskStage.paused, TransferTaskStage.canceled}.contains(ref.notifier(taskProvider).state.tasks[manifest.batchId]?.stage)) {
      return BackupNativeTransferResult(committedMediaKeys: const {}, totalItemCount: manifest.itemCount, errorMessage: '任务已暂停或取消');
    }
    final committedBefore = const BackupReceiptVerifier().verifyPlan(
      currentManifest: manifest,
      expectedTargetFingerprint: target.fingerprint,
      response: planResponse,
    );
    final requiredKeys = planResponse.requiredMediaKeys.toSet();
    String? sessionId;
    String? transferError;

    if (requiredKeys.isNotEmpty) {
      final requiredBindings = <_BackupFileBinding>[];
      final requiredFileIds = <String>[];
      for (var index = 0; index < bindings.length; index++) {
        if (requiredKeys.contains(bindings[index].item.snapshotItem.mediaKey)) {
          requiredBindings.add(bindings[index]);
          requiredFileIds.add(fileIds[index]);
        }
      }
      final uploadManifest = BackupManifest(
        schemaVersion: manifest.schemaVersion,
        batchId: manifest.batchId,
        profileId: manifest.profileId,
        sourceDevice: manifest.sourceDevice,
        createdAtUtc: manifest.createdAtUtc,
        items: requiredBindings.map((binding) => binding.item),
      );
      final uploadMetadata = BackupPrepareMetadata(
        manifest: uploadManifest,
        targetFingerprint: target.fingerprint,
        fileIdToMediaKey: {
          for (var index = 0; index < requiredBindings.length; index++) requiredFileIds[index]: requiredBindings[index].item.snapshotItem.mediaKey,
        },
      );
      sessionId = manifest.batchId;
      try {
        await startSession(
          target: target,
          files: requiredBindings.map((binding) => binding.file).toList(),
          background: true,
          sessionIdOverride: sessionId,
          fileIds: requiredFileIds,
          backupMetadata: uploadMetadata,
          keepSessionOnSuccess: true,
        );
        final session = state[sessionId];
        if (session != null && session.status != SessionStatus.finished) {
          transferError = session.errorMessage ?? session.status.name;
        }
      } catch (error, stackTrace) {
        transferError = error.humanErrorMessage;
        _logger.warning('Native backup transfer failed.', error, stackTrace);
      }
    }

    Set<String> committed = committedBefore;
    try {
      final metadata = BackupManifestMetadata(
        manifest: manifest,
        targetFingerprint: target.fingerprint,
      );
      final response = await _postBackupCommit(
        target,
        BackupCommitRequest(metadata: metadata),
      );
      committed = const BackupReceiptVerifier().verifyCommittedItems(
        currentManifest: manifest,
        expectedTargetFingerprint: target.fingerprint,
        response: response,
      );
    } catch (error, stackTrace) {
      transferError ??= error.humanErrorMessage;
      _logger.warning('Could not obtain the final backup receipt.', error, stackTrace);
    } finally {
      if (sessionId != null && state.containsKey(sessionId)) {
        closeSession(sessionId);
      }
    }

    return BackupNativeTransferResult(
      committedMediaKeys: committed,
      totalItemCount: manifest.itemCount,
      errorMessage: transferError,
    );
  }

  Future<BackupPlanResponse> _postBackupPlan(
    Device target,
    BackupPlanRequest request,
  ) async {
    const codec = BackupProtocolCodec();
    try {
      final response = await ref.read(httpProvider).longLiving.post(
            _backupRouteTarget(target, BackupProtocolRoutes.plan),
            body: HttpBody.json(codec.planRequestToJson(request)),
          );
      return codec.planResponseFromJson(response.bodyToJson);
    } on RhttpStatusCodeException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        throw const BackupProtocolUnavailableException();
      }
      rethrow;
    }
  }

  Future<BackupCommitResponse> _postBackupCommit(
    Device target,
    BackupCommitRequest request,
  ) async {
    const codec = BackupProtocolCodec();
    try {
      final response = await ref.read(httpProvider).longLiving.post(
            _backupRouteTarget(target, BackupProtocolRoutes.commit),
            body: HttpBody.json(codec.commitRequestToJson(request)),
          );
      return codec.commitResponseFromJson(response.bodyToJson);
    } on RhttpStatusCodeException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        throw const BackupProtocolUnavailableException();
      }
      rethrow;
    }
  }

  /// Starts a session.
  /// If [background] is true, then the session closes itself on success and no pages will be open
  /// If [background] is false, then this method will open pages by itself and waits for user input to close the session.
  Future<void> _startSession({
    required Device target,
    required List<CrossFile> files,
    required bool background,
    String? sessionIdOverride,
    List<String>? fileIds,
    BackupPrepareMetadata? backupMetadata,
    bool keepSessionOnSuccess = false,
  }) async {
    final client = ref.read(httpProvider).longLiving;
    final cancelToken = CancelToken();
    final sessionId = sessionIdOverride ?? _uuid.v4();
    final resolvedFileIds = fileIds ?? List<String>.generate(files.length, (_) => _uuid.v4());
    if (resolvedFileIds.length != files.length || resolvedFileIds.toSet().length != resolvedFileIds.length) {
      throw ArgumentError.value(
        fileIds,
        'fileIds',
        'Must contain one unique ID for every file.',
      );
    }
    if (backupMetadata != null &&
        (backupMetadata.fileIdToMediaKey.length != resolvedFileIds.length ||
            !backupMetadata.fileIdToMediaKey.keys.toSet().containsAll(resolvedFileIds))) {
      throw ArgumentError.value(
        backupMetadata.fileIdToMediaKey,
        'backupMetadata',
        'Backup metadata must map every supplied file ID.',
      );
    }

    final requestState = SendSessionState(
      sessionId: sessionId,
      remoteSessionId: null,
      background: background,
      status: SessionStatus.waiting,
      target: target,
      files: Map.fromEntries(await Future.wait(files.indexed.map((entry) async {
        final index = entry.$1;
        final file = entry.$2;
        final id = resolvedFileIds[index];
        return MapEntry(
          id,
          SendingFile(
            file: FileDto(
              id: id,
              fileName: file.name,
              size: file.size,
              fileType: file.fileType,
              hash: null,
              preview: files.length == 1 && files.first.fileType == FileType.text && files.first.bytes != null
                  ? utf8.decode(files.first.bytes!) // send simple message by embedding it into the preview
                  : null,
              metadata: file.lastModified != null || file.lastAccessed != null
                  ? FileMetadata(
                      lastModified: file.lastModified,
                      lastAccessed: file.lastAccessed,
                    )
                  : null,
              legacy: target.version == '1.0',
            ),
            status: FileStatus.queue,
            token: null,
            thumbnail: file.thumbnail,
            asset: file.asset,
            path: file.path,
            bytes: file.bytes,
            errorMessage: null,
          ),
        );
      }))),
      startTime: null,
      endTime: null,
      sendingTasks: [],
      errorMessage: null,
    );

    final originDevice = ref.read(deviceFullInfoProvider);
    final requestDto = PrepareUploadRequestDto(
      info: InfoRegisterDto(
        alias: originDevice.alias,
        version: originDevice.version,
        deviceModel: originDevice.deviceModel,
        deviceType: originDevice.deviceType,
        fingerprint: originDevice.fingerprint,
        port: originDevice.port,
        protocol: originDevice.https ? ProtocolType.https : ProtocolType.http,
        download: originDevice.download,
      ),
      files: {
        for (final entry in requestState.files.entries) entry.key: entry.value.file,
      },
    );
    final Map<String, Object?> requestJson = backupMetadata == null
        ? requestDto.toJson().cast<String, Object?>()
        : const BackupProtocolCodec().attachPrepareMetadata(
            requestDto.toJson().cast<String, Object?>(),
            backupMetadata,
          );
    requestJson['localshareTaskId'] = sessionId;

    state = state.updateSession(
      sessionId: sessionId,
      state: (_) => requestState,
    );

    if (!background) {
      // ignore: use_build_context_synchronously, unawaited_futures
      Routerino.context.push(
        () => SendPage(showAppBar: false, closeSessionOnClose: true, sessionId: sessionId),
        transition: RouterinoTransition.fade(),
      );
    }

    HttpTextResponse? response;
    bool invalidPin;
    bool pinFirstAttempt = true;
    String? pin;
    _prepareRequests.register(sessionId, cancelToken.cancel);
    ref.notifier(taskProvider).queue.release(sessionId);
    try {
      do {
        if (!state.containsKey(sessionId) || cancelToken.isCancelled) {
          return;
        }
        invalidPin = false;
        try {
          response = await client.post(
            ApiRoute.prepareUpload.target(target),
            query: {
              if (pin != null) 'pin': pin,
            },
            body: HttpBody.json(requestJson),
            cancelToken: cancelToken,
          );
        } on RhttpStatusCodeException catch (e) {
          switch (e.statusCode) {
            case 401:
              invalidPin = true;

              // wait until animation is finished
              await sleepAsync(500);
              if (!state.containsKey(sessionId) || cancelToken.isCancelled) {
                return;
              }

              pin = await showDialog<String>(
                // ignore: use_build_context_synchronously
                context: Routerino.context,
                builder: (_) => PinDialog(
                  obscureText: true,
                  showInvalidPin: !pinFirstAttempt,
                ),
              );
              if (!state.containsKey(sessionId) || cancelToken.isCancelled) {
                return;
              }

              pinFirstAttempt = false;

              if (pin == null) {
                state = state.updateSession(
                  sessionId: sessionId,
                  state: (s) => s?.copyWith(
                    status: SessionStatus.canceledBySender,
                  ),
                );
                return;
              }
              break;
            case 403:
              state = state.updateSession(
                sessionId: sessionId,
                state: (s) => s?.copyWith(
                  status: SessionStatus.declined,
                ),
              );
              return;
            case 409:
              state = state.updateSession(
                sessionId: sessionId,
                state: (s) => s?.copyWith(
                  status: SessionStatus.recipientBusy,
                ),
              );
              return;
            case 429:
              state = state.updateSession(
                sessionId: sessionId,
                state: (s) => s?.copyWith(
                  status: SessionStatus.tooManyAttempts,
                ),
              );
              return;
            default:
              state = state.updateSession(
                sessionId: sessionId,
                state: (s) => s?.copyWith(
                  status: SessionStatus.finishedWithErrors,
                  errorMessage: e.humanErrorMessage,
                ),
              );
              return;
          }
        } catch (e) {
          state = state.updateSession(
            sessionId: sessionId,
            state: (s) => s?.copyWith(
              status: SessionStatus.finishedWithErrors,
              errorMessage: e.humanErrorMessage,
            ),
          );
          return;
        }
      } while (invalidPin);
    } finally {
      _prepareRequests.finish(sessionId);
    }

    if (response == null) {
      return;
    }

    final Map<String, String> fileMap;
    if (target.version == '1.0') {
      fileMap = (response.bodyToJson as Map).cast<String, String>();
    } else {
      if (response.statusCode == 204) {
        // Nothing selected
        // Interpret this as "Read and close"
        fileMap = {};
      } else {
        try {
          if ((response.bodyToJson as Map)['localshareAdmission'] == 1) {
            _admissionSessions.add(sessionId);
          }
          if ((response.bodyToJson as Map)['localshareResume'] == 1) {
            _resumableSessions.add(sessionId);
          }
          final responseDto = PrepareUploadResponseDto.fromJson(response.bodyToJson);
          fileMap = responseDto.files;
          state = state.updateSession(
            sessionId: sessionId,
            state: (s) => s?.copyWith(
              remoteSessionId: responseDto.sessionId,
            ),
          );
          final manager = ref.notifier(taskProvider);
          final task = manager.state.tasks[sessionId];
          if (task != null) {
            manager.put(task.copyWith(stage: task.stage, retryData: {...task.retryData, 'remoteSessionId': responseDto.sessionId}));
          }
        } catch (e) {
          state = state.updateSession(
            sessionId: sessionId,
            state: (s) => s?.copyWith(
              status: SessionStatus.finishedWithErrors,
              errorMessage: e.humanErrorMessage,
            ),
          );
          return;
        }
      }
    }

    if (fileMap.isEmpty) {
      // receiver has nothing selected
      state = state.updateSession(
        sessionId: sessionId,
        state: (s) => s?.copyWith(
          status: SessionStatus.finished,
        ),
      );

      if (state[sessionId]?.background == false) {
        // ignore: use_build_context_synchronously, unawaited_futures
        Routerino.context.pushRootImmediately(() => const HomePage(initialTab: HomeTab.home, appStart: false));
      }

      closeSession(sessionId);
      return;
    }

    final sendingFiles = {
      for (final file in requestState.files.values)
        file.file.id: fileMap.containsKey(file.file.id) ? file.copyWith(token: fileMap[file.file.id]) : file.copyWith(status: FileStatus.skipped),
    };

    if (state[sessionId]?.background == false) {
      final background = ref.read(settingsProvider).sendMode == SendMode.multiple;

      // ignore: use_build_context_synchronously, unawaited_futures
      Routerino.context.pushAndRemoveUntil(
        removeUntil: HomePage,
        transition: RouterinoTransition.fade(),
        // immediately is not possible: https://github.com/flutter/flutter/issues/121910
        builder: () => ProgressPage(
          showAppBar: background,
          closeSessionOnClose: !background,
          sessionId: sessionId,
        ),
      );
    }

    state = state.updateSession(
      sessionId: sessionId,
      state: (s) => s?.copyWith(
        status: SessionStatus.sending,
        files: sendingFiles,
      ),
    );

    final manager = ref.notifier(taskProvider);
    _prepareRequests.register(sessionId, cancelToken.cancel);
    try {
      while (true) {
        manager.update(sessionId, TransferTaskStage.queued);
        if (!await manager.queue.acquire(sessionId, media: backupMetadata != null)) return;
        if (!state.containsKey(sessionId) ||
            cancelToken.isCancelled ||
            {TransferTaskStage.paused, TransferTaskStage.canceled}.contains(manager.state.tasks[sessionId]?.stage)) {
          manager.queue.release(sessionId);
          return;
        }
        if (!_admissionSessions.contains(sessionId)) break;
        try {
          await ref.read(httpProvider).discovery.post(_backupRouteTarget(target, '/api/localshare/v1/transfer/start'),
              query: {'sessionId': state[sessionId]!.remoteSessionId!, 'token': fileMap.values.first},
              body: HttpBody.json(const {}),
              cancelToken: cancelToken);
          break;
        } on RhttpStatusCodeException catch (error) {
          if (error.statusCode != 409) rethrow;
          manager.queue.release(sessionId);
          await Future<void>.delayed(Duration(milliseconds: 300 + DateTime.now().microsecond % 1200));
        }
      }
    } finally {
      _prepareRequests.finish(sessionId);
    }
    manager.update(sessionId, TransferTaskStage.running);
    await _sendLoop(
      ref,
      sessionId,
      target,
      sendingFiles,
      keepSessionOnSuccess: keepSessionOnSuccess,
    );
  }

  Future<void> _sendLoop(
    Ref ref,
    String sessionId,
    Device target,
    Map<String, SendingFile> files, {
    bool keepSessionOnSuccess = false,
  }) async {
    state = state.updateSession(
      sessionId: sessionId,
      state: (s) => s?.copyWith(startTime: DateTime.now().millisecondsSinceEpoch),
    );

    final queue = Queue<SendingFile>()..addAll(files.values);
    const concurrency = 1;
    _logger.info('Sending files using $concurrency concurrent isolates');

    final futures = List.generate(concurrency, (index) async {
      while (true) {
        final file = switch (queue.isEmpty) {
          true => null,
          false => queue.removeFirst(),
        };

        if (file == null) {
          break;
        }

        await sendFile(
          sessionId: sessionId,
          isolateIndex: index,
          file: file,
          isRetry: false,
        );
      }
    });

    await Future.wait(futures);

    _finish(
      sessionId: sessionId,
      keepSessionOnSuccess: keepSessionOnSuccess,
    );
  }

  void _finish({
    required String sessionId,
    bool keepSessionOnSuccess = false,
  }) {
    final sessionState = state[sessionId];
    if (sessionState == null) {
      return;
    }

    if (state[sessionId]!.status != SessionStatus.sending) {
      _logger.info('Transfer was canceled.');
    } else {
      final hasError = sessionState.files.values.any((file) => file.status == FileStatus.failed);
      if (!hasError && sessionState.background == true && !keepSessionOnSuccess) {
        // close session because everything is fine and it is in background
        closeSession(sessionId);
        _logger.info('Transfer finished and session removed.');
      } else {
        // keep session alive when there are errors or currently in foreground
        state = state.updateSession(
          sessionId: sessionId,
          state: (s) => s?.copyWith(
            status: hasError ? SessionStatus.finishedWithErrors : SessionStatus.finished,
            endTime: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        if (hasError) {
          _logger.info('Transfer finished with errors.');
        } else {
          _logger.info('Transfer finished successfully.');
        }
      }
    }
  }

  final uriContent = UriContent();

  /// Sends a file.
  /// Returns true, if the next file should be sent.
  Future<bool> sendFile({
    required String sessionId,
    required int isolateIndex,
    required SendingFile file,
    required bool isRetry,
  }) async {
    final token = file.token;
    if (token == null) {
      return true;
    }

    final status = state[sessionId]?.status;
    const allowedStates = {SessionStatus.sending, SessionStatus.finishedWithErrors};
    if (status == null || !allowedStates.contains(status)) {
      return false;
    }

    final remoteSessionId = state[sessionId]!.remoteSessionId;
    final target = state[sessionId]!.target;

    if (isRetry) {
      _logger.info('Retrying ${file.file.fileName}');

      state = state.updateSession(
        sessionId: sessionId,
        state: (s) => s?.copyWith(
          status: SessionStatus.sending,
          files: s.files.map((key, value) {
            if (key == file.file.id) {
              return MapEntry(key, value.copyWith(status: FileStatus.queue, errorMessage: null));
            }
            return MapEntry(key, value);
          }),
        ),
      );
    } else {
      _logger.info('Sending ${file.file.fileName}');
    }

    state = state.updateSession(
      sessionId: sessionId,
      state: (s) => s?.withFileStatus(file.file.id, FileStatus.sending, null),
    );

    final taskResult = ref.redux(parentIsolateProvider).dispatchTakeResult(IsolateHttpUploadAction(
          resumable: _resumableSessions.contains(sessionId),
          isolateIndex: isolateIndex,
          remoteSessionId: remoteSessionId,
          remoteFileToken: token,
          fileId: file.file.id,
          filePath: file.path,
          fileBytes: file.bytes,
          mime: file.file.lookupMime(),
          fileSize: file.file.size,
          device: target,
        ));

    String? fileError;
    try {
      state = state.updateSession(
        sessionId: sessionId,
        state: (s) => s?.copyWith(sendingTasks: [
          ...?s.sendingTasks,
          SendingTask(
            isolateIndex: isolateIndex,
            taskId: taskResult.taskId,
          ),
        ]),
      );

      await for (final progress in taskResult.progress) {
        ref.notifier(progressProvider).setProgress(
              sessionId: sessionId,
              fileId: file.file.id,
              progress: progress,
            );
      }

      // set progress to 100% when successfully finished
      ref.notifier(progressProvider).setProgress(
            sessionId: sessionId,
            fileId: file.file.id,
            progress: 1,
          );
    } catch (e, st) {
      fileError = e.humanErrorMessage;
      _logger.warning('Error while sending file ${file.file.fileName}', e, st);
    } finally {
      state = state.updateSession(
        sessionId: sessionId,
        state: (s) => s?.copyWith(
            sendingTasks: s.sendingTasks?.where((task) => !(task.isolateIndex == isolateIndex && task.taskId == taskResult.taskId)).toList()),
      );
    }

    state = state.updateSession(
      sessionId: sessionId,
      state: (s) => s?.withFileStatus(file.file.id, fileError != null ? FileStatus.failed : FileStatus.finished, fileError),
    );

    if (isRetry) {
      final state = this.state[sessionId];
      if (state != null && state.files.values.map((e) => e.status).isFinishedOrError) {
        _finish(sessionId: sessionId);
        return false;
      }
    }

    return true;
  }

  /// Closes the send-session and sends a cancel event to the receiver.
  void cancelSession(String sessionId) {
    ref.notifier(taskProvider).update(sessionId, TransferTaskStage.canceled);
    ref.notifier(taskProvider).queue.release(sessionId);
    _prepareRequests.cancel(sessionId);
    final sessionState = state[sessionId];
    if (sessionState == null) {
      return;
    }
    final remoteSessionId = sessionState.remoteSessionId;
    final fallbackId = sha256.convert(utf8.encode('${ref.read(deviceFullInfoProvider).fingerprint}:$sessionId')).toString();

    _cancelRunningRequests(sessionState);

    // notify the receiver
    unawaited(ref
        .read(httpProvider)
        .discovery
        .post(ApiRoute.cancel.target(sessionState.target, query: {'sessionId': remoteSessionId ?? fallbackId}))
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {
      _logger.warning('Error while canceling session', error, stack);
    }));

    // finally, close session locally
    closeSession(sessionId);
  }

  void cancelSessionByReceiver(String sessionId) {
    ref.notifier(taskProvider).queue.release(sessionId);
    _prepareRequests.cancel(sessionId);
    final sessionState = state[sessionId];
    if (sessionState == null) {
      return;
    }
    _cancelRunningRequests(sessionState);

    state = state.updateSession(
      sessionId: sessionId,
      state: (s) => s?.copyWith(
        status: SessionStatus.canceledByReceiver,
        endTime: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _cancelRunningRequests(SendSessionState state) {
    for (final task in state.sendingTasks ?? <SendingTask>[]) {
      ref.redux(parentIsolateProvider).dispatch(IsolateHttpUploadCancelAction(
            isolateIndex: task.isolateIndex,
            taskId: task.taskId,
          ));
    }
  }

  /// Closes the session
  void closeSession(String sessionId, {bool clearSelection = true}) {
    _prepareRequests.cancel(sessionId);
    final sessionState = state[sessionId];
    if (sessionState == null) {
      return;
    }
    state = state.removeSession(ref, sessionId);
    if (clearSelection && sessionState.status == SessionStatus.finished && ref.read(settingsProvider).sendMode == SendMode.single) {
      // clear selected files
      ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    }
  }

  void clearAllSessions() {
    _prepareRequests.cancelAll();
    state = {};
    ref.notifier(progressProvider).removeAllSessions();
  }

  void setBackground(String sessionId, bool background) {
    state = state.updateSession(sessionId: sessionId, state: (s) => s?.copyWith(background: background));
  }
}

/// Keeps the long-lived prepare request cancelable while the receiver waits
/// for the user to approve or decline a transfer.
class PrepareRequestCancelRegistry {
  final Map<String, void Function()> _requests = {};

  int get activeCount => _requests.length;

  void register(String sessionId, void Function() cancel) {
    final previous = _requests.remove(sessionId);
    previous?.call();
    _requests[sessionId] = cancel;
  }

  void finish(String sessionId) {
    _requests.remove(sessionId);
  }

  void cancel(String sessionId) {
    _requests.remove(sessionId)?.call();
  }

  void cancelAll() {
    final requests = _requests.values.toList(growable: false);
    _requests.clear();
    for (final cancel in requests) {
      cancel();
    }
  }
}

extension on Map<String, SendSessionState> {
  Map<String, SendSessionState> updateSession({
    required String sessionId,
    required SendSessionState? Function(SendSessionState? old) state,
  }) {
    final newState = state(this[sessionId]);
    if (newState == null) {
      // no change
      return this;
    }
    return {
      ...this,
      sessionId: newState,
    };
  }

  Map<String, SendSessionState> removeSession(Ref ref, String sessionId) {
    ref.notifier(progressProvider).removeSession(sessionId);
    return {...this}..remove(sessionId);
  }
}

extension on SendSessionState {
  SendSessionState withFileStatus(String fileId, FileStatus status, String? errorMessage) {
    return copyWith(
      files: {...files}..update(
          fileId,
          (file) => file.copyWith(
            status: status,
            errorMessage: errorMessage,
          ),
        ),
    );
  }
}

final class _BackupFileBinding {
  const _BackupFileBinding({required this.file, required this.item});

  final CrossFile file;
  final BackupManifestItem item;
}

List<_BackupFileBinding> _bindBackupFiles(
  List<CrossFile> files,
  BackupManifest manifest,
) {
  if (files.length != manifest.itemCount) {
    throw ArgumentError.value(
      files.length,
      'files',
      'File count does not match the backup manifest.',
    );
  }
  final itemsByPath = <String, BackupManifestItem>{
    for (final item in manifest.items) '${item.snapshotItem.relativePath}${item.snapshotItem.displayName}': item,
  };
  final bindings = <_BackupFileBinding>[];
  for (final file in files) {
    final item = itemsByPath.remove(file.name);
    if (item == null || item.snapshotItem.sizeBytes != file.size) {
      throw ArgumentError.value(
        file.name,
        'files',
        'File does not match the current backup manifest.',
      );
    }
    bindings.add(_BackupFileBinding(file: file, item: item));
  }
  if (itemsByPath.isNotEmpty) {
    throw ArgumentError.value(
      itemsByPath.keys.toList(),
      'manifest',
      'Manifest contains files that are not available for upload.',
    );
  }
  return List<_BackupFileBinding>.unmodifiable(bindings);
}

String _backupRouteTarget(Device target, String path) {
  return Uri(
    scheme: target.https ? 'https' : 'http',
    host: target.ip,
    port: target.port,
    path: path,
  ).toString();
}

extension on Object {
  String get humanErrorMessage {
    final e = this;
    final (statusCode, message) = switch (this) {
      RhttpStatusCodeException(:final statusCode, :final body) => (statusCode, _parseErrorMessage(body)),
      _ => (null, e.toString()),
    };

    if (statusCode != null && message != null) {
      return '[$statusCode] $message';
    }

    return e.toString();
  }
}

String? _parseErrorMessage(Object? body) {
  if (body is! String) {
    return null;
  }

  try {
    return (jsonDecode(body) as Map)['message'];
  } catch (_) {
    return null;
  }
}
