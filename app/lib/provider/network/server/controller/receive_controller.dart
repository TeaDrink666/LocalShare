import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:common/api_route_builder.dart';
import 'package:common/constants.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/dto/info_dto.dart';
import 'package:common/model/dto/info_register_dto.dart';
import 'package:common/model/dto/prepare_upload_request_dto.dart';
import 'package:common/model/dto/prepare_upload_response_dto.dart';
import 'package:common/model/dto/register_dto.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/file_type.dart';
import 'package:common/model/session_status.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/protocol/protocol.dart';
import 'package:localsend_app/features/backup/receiver/backup_destination_path.dart';
import 'package:localsend_app/features/backup/receiver/backup_file_writer.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_coordinator.dart';
import 'package:localsend_app/features/tasks/resumable_file_store.dart';
import 'package:localsend_app/features/tasks/task_destination.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/controller/common.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/provider/network/web_gateway/web_gateway_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/selection/selected_receiving_files_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/file_saver.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/transfer_foreground_service.dart';
import 'package:localsend_app/util/native/tray_helper.dart';
import 'package:localsend_app/util/simple_server.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

const _uuid = Uuid();

final _logger = Logger('ReceiveController');

/// Handles all requests for receiving files.
class ReceiveController {
  final ServerUtils server;
  final BackupReceiptCoordinator backupReceiptCoordinator;
  final BackupFileWriter _backupFileWriter;
  final String? fixedSessionId;
  final _controllers = <String, ReceiveController>{};
  final _approvedSelections = <String, (String, Map<String, String>)>{};
  Map<String, String>? previousSelection;
  void Function(Map<String, String>)? onAccepted;
  String? _transferId;
  bool _isMedia = false;

  ReceiveController(
    this.server, {
    required this.backupReceiptCoordinator,
    BackupFileWriter backupFileWriter = const BackupFileWriter(),
    this.fixedSessionId,
    this.previousSelection,
    this.onAccepted,
  }) : _backupFileWriter = backupFileWriter;

  ReceiveController? controllerFor(String? id) => _controllers[id ?? server.getStateOrNull()?.session?.sessionId];

  Future<void> _dispatchPrepare(
      {required HttpRequest request, required int port, required bool https, required String fingerprint, required bool v2}) async {
    final payload = await request.readAsString();
    String id = _uuid.v4();
    String approvalSignature = '';
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final task = json['localshareTaskId'];
      approvalSignature = sha256.convert(utf8.encode(jsonEncode(json['files']))).toString();
      if (task is String && RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(task)) {
        id = sha256.convert(utf8.encode('${(json['info'] as Map)['fingerprint']}:$task')).toString();
      }
    } on Object {
      return request.respondJson(400, message: 'Request body malformed');
    }
    final current = server.getState().sessions[id];
    if (current != null && (current.status == SessionStatus.waiting || current.status == SessionStatus.sending)) {
      return request.respondJson(409, message: 'Task already active');
    }
    if (!v2 &&
        server
            .getState()
            .sessions
            .values
            .any((s) => s.sender.ip == request.ip && (s.status == SessionStatus.waiting || s.status == SessionStatus.sending))) {
      return request.respondJson(409, message: 'Legacy client already has a session');
    }
    _controllers[id]?.closeSession();
    final controller = ReceiveController(server.forSession(id),
        backupReceiptCoordinator: backupReceiptCoordinator,
        fixedSessionId: id,
        previousSelection: _approvedSelections[id]?.$1 == approvalSignature ? {..._approvedSelections[id]!.$2} : null, onAccepted: (selection) {
      _approvedSelections[id] = (approvalSignature, {...selection});
    });
    _controllers[id] = controller;
    server.ref.notifier(taskProvider).disposals[id] = () {
      controller.closeSession();
      _controllers.remove(id);
      _approvedSelections.remove(id);
    };
    return controller._prepareUploadHandler(request: request, port: port, https: https, fingerprint: fingerprint, v2: v2, payloadOverride: payload);
  }

  ReceiveController? _requestController(HttpRequest request, bool v2) {
    if (v2) return _controllers[request.uri.queryParameters['sessionId']];
    final sessions = server.getState().sessions.values.where((s) => s.sender.ip == request.ip && s.sender.version == '1.0');
    return sessions.length == 1 ? _controllers[sessions.single.sessionId] : null;
  }

  /// Installs all routes for receiving files.
  void installRoutes({
    required SimpleServerRouteBuilder router,
    required String alias,
    required int port,
    required bool https,
    required String fingerprint,
    required String showToken,
  }) {
    router.get('/web-receive', (HttpRequest request) async {
      request.response.headers
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('x-content-type-options', 'nosniff')
        ..set('referrer-policy', 'no-referrer')
        ..set('x-frame-options', 'DENY')
        ..set(
          'content-security-policy',
          "default-src 'self'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
        );
      return await request.respondAsset(200, 'assets/web/receive.html');
    });

    router.get('/web-receive.js', (HttpRequest request) async {
      request.response.headers
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('x-content-type-options', 'nosniff');
      return await request.respondAsset(200, 'assets/web/receive.js', 'text/javascript; charset=utf-8');
    });

    router.get(ApiRoute.info.v1, (HttpRequest request) async {
      return await _infoHandler(request: request, alias: alias, fingerprint: fingerprint);
    });

    router.get(ApiRoute.info.v2, (HttpRequest request) async {
      return await _infoHandler(request: request, alias: alias, fingerprint: fingerprint);
    });

    // An upgraded version of /info
    router.post(ApiRoute.register.v1, (HttpRequest request) async {
      return await _registerHandler(request: request, alias: alias, port: port, https: https, fingerprint: fingerprint);
    });

    router.post(ApiRoute.register.v2, (HttpRequest request) async {
      return await _registerHandler(request: request, alias: alias, port: port, https: https, fingerprint: fingerprint);
    });

    router.post(ApiRoute.prepareUpload.v1, (HttpRequest request) async {
      return await _dispatchPrepare(
        request: request,
        port: port,
        https: https,
        fingerprint: fingerprint,
        v2: false,
      );
    });

    router.post(ApiRoute.prepareUpload.v2, (HttpRequest request) async {
      return await _dispatchPrepare(
        request: request,
        port: port,
        https: https,
        fingerprint: fingerprint,
        v2: true,
      );
    });

    router.post(ApiRoute.upload.v1, (HttpRequest request) async {
      final controller = _requestController(request, false);
      if (controller == null) {
        return request.respondJson(409, message: 'No session');
      }
      return await controller._uploadHandler(request: request, v2: false);
    });

    router.post(ApiRoute.upload.v2, (HttpRequest request) async {
      final controller = _requestController(request, true);
      if (controller == null) {
        return request.respondJson(409, message: 'No session');
      }
      return await controller._uploadHandler(request: request, v2: true);
    });

    router.post(ApiRoute.cancel.v1, (HttpRequest request) async {
      final controller = _requestController(request, false) ??
          ReceiveController(server.forSession('outgoing-cancel'), backupReceiptCoordinator: backupReceiptCoordinator);
      return await controller._cancelHandler(request: request, v2: false);
    });

    router.post(ApiRoute.cancel.v2, (HttpRequest request) async {
      final controller = _requestController(request, true) ??
          ReceiveController(server.forSession('outgoing-cancel'), backupReceiptCoordinator: backupReceiptCoordinator);
      return await controller._cancelHandler(request: request, v2: true);
    });

    router.post(ApiRoute.show.v1, (HttpRequest request) async {
      return await _showHandler(request: request, showToken: showToken);
    });

    router.post(ApiRoute.show.v2, (HttpRequest request) async {
      return await _showHandler(request: request, showToken: showToken);
    });
    router.get('/api/localshare/v1/transfer/status', (request) async {
      final controller = _requestController(request, true);
      if (controller == null) {
        return request.respondJson(409, message: 'No session');
      }
      return controller._resumeHandler(request, chunk: false);
    });
    router.post('/api/localshare/v1/transfer/start', (request) async {
      final controller = _requestController(request, true);
      if (controller == null) {
        return request.respondJson(409, message: 'No session');
      }
      return controller._admit(request);
    });
    router.post('/api/localshare/v1/transfer/chunk', (request) async {
      final controller = _requestController(request, true);
      if (controller == null) {
        return request.respondJson(409, message: 'No session');
      }
      return controller._resumeHandler(request, chunk: true);
    });
  }

  Future<void> _infoHandler({
    required HttpRequest request,
    required String alias,
    required String fingerprint,
  }) async {
    final senderFingerprint = request.uri.queryParameters['fingerprint'];
    if (senderFingerprint == fingerprint) {
      // "I talked to myself lol"
      return await request.respondJson(412, message: 'Self-discovered');
    }

    final deviceInfo = server.ref.read(deviceInfoProvider);

    final dto = InfoDto(
      alias: alias,
      version: protocolVersion,
      deviceModel: deviceInfo.deviceModel,
      deviceType: deviceInfo.deviceType,
      fingerprint: fingerprint,
      download: server.ref.read(webGatewayProvider)?.webSendState != null,
    );

    return await request.respondJson(200, body: dto.toJson());
  }

  Future<void> _registerHandler({
    required HttpRequest request,
    required String alias,
    required String fingerprint,
    required int port,
    required bool https,
  }) async {
    final payload = await request.readAsString();
    final RegisterDto requestDto;
    try {
      requestDto = RegisterDto.fromJson(jsonDecode(payload));
    } catch (e) {
      return await request.respondJson(400, message: 'Request body malformed');
    }

    if (requestDto.fingerprint == fingerprint) {
      // "I talked to myself lol"
      return await request.respondJson(412, message: 'Self-discovered');
    }

    // Save device information
    await server.ref.redux(nearbyDevicesProvider).dispatchAsync(RegisterDeviceAction(requestDto.toDevice(request.ip, port, https)));
    server.ref.notifier(discoveryLoggerProvider).addLog('[DISCOVER/TCP] Received "/register" HTTP request: ${requestDto.alias} (${request.ip})');

    final deviceInfo = server.ref.read(deviceInfoProvider);

    final responseDto = InfoDto(
      alias: alias,
      version: protocolVersion,
      deviceModel: deviceInfo.deviceModel,
      deviceType: deviceInfo.deviceType,
      fingerprint: fingerprint,
      download: server.ref.read(webGatewayProvider)?.webSendState != null,
    );

    return await request.respondJson(200, body: responseDto.toJson());
  }

  Future<void> _prepareUploadHandler({
    required HttpRequest request,
    required int port,
    required bool https,
    required String fingerprint,
    required bool v2,
    String? payloadOverride,
  }) async {
    if (server.getState().session != null) {
      // block incoming requests when we are already in a session
      return await request.respondJson(409, message: 'Blocked by another session');
    }

    final pinCorrect = await checkPin(
      pin: server.ref.read(settingsProvider).receivePin,
      pinAttempts: server.getState().pinAttempts,
      request: request,
    );
    if (!pinCorrect) {
      return;
    }

    final PrepareUploadRequestDto dto;
    final BackupPrepareMetadata? backupMetadata;
    try {
      final payload = payloadOverride ?? await request.readAsString();
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Request body must be an object.');
      }
      _transferId = decoded['localshareTaskId'] as String?;
      dto = PrepareUploadRequestDto.fromJson(decoded);
      backupMetadata = decoded.containsKey(localShareBackupMetadataField)
          ? const BackupProtocolCodec().prepareMetadataFromRequestJson(
              decoded.cast<String, Object?>(),
            )
          : null;
    } catch (e) {
      return await request.respondJson(400, message: 'Request body malformed');
    }

    if (dto.files.isEmpty) {
      // block empty requests (at least one file is required)
      return await request.respondJson(400, message: 'Request must contain at least one file');
    }

    if (backupMetadata != null) {
      if (!v2) {
        return await request.respondJson(
          400,
          message: 'Native backup requires protocol v2.',
        );
      }
      if (backupMetadata.targetFingerprint != fingerprint) {
        return await request.respondJson(
          412,
          message: 'Backup target fingerprint mismatch.',
        );
      }
      if (backupMetadata.manifest.sourceDevice != dto.info.fingerprint) {
        return await request.respondJson(
          403,
          message: 'Backup source fingerprint mismatch.',
        );
      }
      final descriptorError = _validateBackupFileDescriptors(
        metadata: backupMetadata,
        files: dto.files,
      );
      if (descriptorError != null) {
        return await request.respondJson(400, message: descriptorError);
      }
    }

    final settings = server.ref.read(settingsProvider);
    var destinationDir = normalizeDestinationDirectory(
      backupMetadata == null
          ? settings.destination ?? await getDefaultDestinationDirectory()
          : settings.backupDestination ?? await getDefaultBackupDestinationDirectory(),
    );
    final cacheDir = await getCacheDirectory();
    if (dto.files.entries.any((entry) => entry.value.size < 0 || entry.value.id != entry.key)) {
      return request.respondJson(400, message: 'Invalid file descriptors');
    }
    final sessionId = fixedSessionId ?? _uuid.v4();
    _isMedia = backupMetadata != null;
    final tasks = server.ref.notifier(taskProvider);
    final previousTask = tasks.state.tasks[sessionId];
    if (backupMetadata == null) {
      try {
        validateTaskPaths(dto.files.values.map((file) => file.fileName));
      } catch (error) {
        return request.respondJson(400, message: error.toString());
      }
      if (destinationDir.startsWith('content://')) {
        // The system picker grants access to this tree; create task-relative
        // paths through the existing SAF directory creation adapter.
        final folder = previousTask?.retryData['taskFolder'] as String? ?? taskDirectoryName(sessionId, DateTime.now());
        _taskFolder = folder;
      } else {
        destinationDir = previousTask?.directory ?? p.join(destinationDir, taskDirectoryName(sessionId, DateTime.now()));
      }
    }
    tasks.put(TransferTask(
        id: sessionId,
        kind: backupMetadata == null ? TransferTaskKind.receive : TransferTaskKind.backup,
        peer: dto.info.alias,
        createdAt: previousTask?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        stage: TransferTaskStage.waiting,
        directory: destinationDir,
        files: dto.files.values.map((f) => <String, dynamic>{'id': f.id, 'name': f.fileName, 'size': f.size, 'status': 'queue'}).toList(),
        retryData: {'admission': _transferId != null, 'taskFolder': _taskFolder, 'transferId': _transferId, 'fingerprint': dto.info.fingerprint}));
    tasks.cancellations[sessionId] = cancelSession;
    tasks.acceptances[sessionId] = () => acceptFileRequest({for (final file in dto.files.values) file.id: file.fileName});
    tasks.declines[sessionId] = declineFileRequest;

    Set<String> alreadyVerifiedMediaKeys = const {};
    if (backupMetadata != null) {
      try {
        final receipt = await backupReceiptCoordinator.receipt(
          backupMetadata.manifestMetadata,
        );
        alreadyVerifiedMediaKeys = receipt.committedItems.map((item) => item.mediaKey).toSet();
      } catch (error, stackTrace) {
        _logger.warning('Could not read the backup receipt ledger.', error, stackTrace);
        return await request.respondJson(
          409,
          message: 'Could not read the backup receipt ledger: $error',
        );
      }
    }

    _logger.info('Session Id: $sessionId');
    _logger.info('Destination Directory: $destinationDir');

    final streamController = StreamController<Map<String, String>?>();
    server.setState(
      (oldState) => oldState?.copyWith(
        session: ReceiveSessionState(
          sessionId: sessionId,
          status: SessionStatus.waiting,
          sender: dto.info.toDevice(request.ip, port, https),
          senderAlias: server.ref.read(favoritesProvider).firstWhereOrNull((e) => e.fingerprint == dto.info.fingerprint)?.alias ?? dto.info.alias,
          files: {
            for (final file in dto.files.values)
              file.id: ReceivingFile(
                file: file,
                status: FileStatus.queue,
                token: null,
                desiredName: null,
                path: null,
                savedToGallery: false,
                errorMessage: null,
              ),
          },
          startTime: null,
          endTime: null,
          destinationDirectory: destinationDir,
          cacheDirectory: cacheDir,
          saveToGallery: false,
          createdDirectories: {},
          responseHandler: streamController,
        ),
      ),
    );

    // Keep the process alive with the screen off while a long transfer runs.
    _foregroundActive = true;
    unawaited(startTransferForegroundService());

    bool quickSave = settings.quickSave && server.getState().session?.message == null;
    final quickSaveFromFavorites = settings.quickSaveFromFavorites && server.getState().session?.message == null;
    if (quickSaveFromFavorites) {
      final bool isFavorite = server.ref.read(favoritesProvider).any((e) => e.fingerprint == dto.info.fingerprint);
      if (isFavorite) {
        quickSave = true;
      }
    }
    final Map<String, String>? selection;
    if (quickSave || previousSelection != null) {
      // accept all files
      selection = previousSelection ??
          {
            for (final f in dto.files.values) f.id: f.fileName,
          };
    } else {
      if (checkPlatformHasTray() && (await windowManager.isMinimized() || !(await windowManager.isVisible()) || !(await windowManager.isFocused()))) {
        await showFromTray();
      }

      final message = server.getState().session?.message;
      if (message != null) {
        // Message already received
        await server.ref.redux(receiveHistoryProvider).dispatchAsync(AddHistoryEntryAction(
              entryId: const Uuid().v4(),
              fileName: message,
              fileType: FileType.text,
              path: null,
              savedToGallery: false,
              isMessage: true,
              fileSize: message.length,
              senderAlias: server.getState().session!.senderAlias,
              timestamp: DateTime.now().toUtc(),
            ));
      } else {
        server.ref.notifier(selectedReceivingFilesProvider).setFiles(server.getState().session!.files.values.map((f) => f.file).toList());
      }

      if (server.ref.read(homePageControllerProvider).currentTab != HomeTab.home) {
        server.ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.tasks));
      }

      // Delayed response (waiting for user's decision)
      selection = await streamController.stream.first;
    }

    if (server.getState().session == null) {
      // somehow this state is already disposed
      return await request.respondJson(500, message: 'Server is in invalid state');
    }

    if (selection == null) {
      closeSession();
      return await request.respondJson(403, message: 'File request declined by recipient');
    }

    if (backupMetadata != null && alreadyVerifiedMediaKeys.isNotEmpty) {
      selection.removeWhere((fileId, _) {
        final mediaKey = backupMetadata!.fileIdToMediaKey[fileId];
        return mediaKey != null && alreadyVerifiedMediaKeys.contains(mediaKey);
      });
    }

    if (selection.isEmpty) {
      // nothing selected, send this to sender and close session
      // This usually happens for message transfers
      closeSession();
      return await request.respondJson(204);
    }

    tasks.update(sessionId, TransferTaskStage.queued);
    onAccepted?.call(selection);
    final admitted =
        _transferId != null || await tasks.queue.acquire(sessionId, media: _isMedia).timeout(const Duration(seconds: 3), onTimeout: () => false);
    if (!admitted || server.getStateOrNull()?.session == null) {
      tasks.queue.release(sessionId);
      closeSession();
      tasks.update(sessionId, TransferTaskStage.interrupted, error: '接收端忙碌，等待发送端重新连接');
      return request.respondJson(409, message: 'Receiver queue busy');
    }
    if (!destinationDir.startsWith('content://')) {
      await Directory(destinationDir).create(recursive: true);
    }

    if (backupMetadata != null) {
      try {
        await backupReceiptCoordinator.attachSession(
          sessionId: sessionId,
          senderFingerprint: backupMetadata.manifest.sourceDevice,
          metadata: backupMetadata,
        );
      } catch (error, stackTrace) {
        _logger.warning(
          'Could not prepare the backup receipt session.',
          error,
          stackTrace,
        );
        closeSession();
        return await request.respondJson(
          409,
          message: 'Could not prepare the backup receipt ledger: $error',
        );
      }
    }

    server.setState(
      (oldState) {
        final receiveState = oldState!.session!;
        return oldState.copyWith(
          session: receiveState.copyWith(
            status: SessionStatus.sending,
            files: Map.fromEntries(
              receiveState.files.values.map((entry) {
                final desiredName = selection!.containsKey(entry.file.id) ? entry.file.fileName : null;
                return MapEntry(
                  entry.file.id,
                  ReceivingFile(
                    file: entry.file,
                    status: desiredName != null ? FileStatus.queue : FileStatus.skipped,
                    token: desiredName != null ? _uuid.v4() : null,
                    desiredName: desiredName,
                    path: null,
                    savedToGallery: false,
                    errorMessage: null,
                  ),
                );
              }),
            ),
            responseHandler: null,
          ),
        );
      },
    );

    final files = {
      for (final file in server.getState().session!.files.values.where((f) => f.token != null)) file.file.id: file.token,
    };

    if (checkPlatform([TargetPlatform.android, TargetPlatform.iOS])) {
      if (checkPlatform([TargetPlatform.android]) && !server.getState().session!.destinationDirectory.startsWith('/storage/emulated/0/Download')) {
        // Android requires more permission to save files outside of the Download directory
        try {
          final result = await Permission.storage.request();
          _logger.info('storage permission: $result');
        } catch (e) {
          _logger.warning('Could not request storage permission', e);
        }
      }
      try {
        await Permission.storage.request();
      } catch (e) {
        _logger.warning('Could not request storage permission', e);
      }
    }

    if (v2) {
      return await request.respondJson(200, body: {
        ...PrepareUploadResponseDto(
          sessionId: sessionId,
          files: files.cast(),
        ).toJson(),
        'localshareAdmission': _transferId != null ? 1 : 0,
        'localshareResume': _transferId != null && !destinationDir.startsWith('content://') ? 1 : 0
      });
    }

    return await request.respondJson(200, body: files);
  }

  Future<void> _uploadHandler({
    required HttpRequest request,
    required bool v2,
    Stream<Uint8List>? bytesOverride,
    Future<void> Function(String path)? onCommitted,
    Future<void> Function(String path)? beforePublish,
  }) async {
    final receiveState = server.getState().session;
    if (receiveState == null) {
      return await request.respondJson(409, message: 'No session');
    }

    if (request.ip != receiveState.sender.ip) {
      _logger.warning('Invalid ip address: ${request.ip} (expected: ${receiveState.sender.ip})');
      return await request.respondJson(403, message: 'Invalid IP address: ${request.ip}');
    }

    const allowedStates = {SessionStatus.sending, SessionStatus.finishedWithErrors};
    if (!allowedStates.contains(receiveState.status)) {
      _logger.warning('Wrong state: ${receiveState.status}');
      return await request.respondJson(409, message: 'Recipient is in wrong state');
    }

    if (!server.ref.notifier(taskProvider).queue.isActive(receiveState.sessionId)) {
      return request.respondJson(409, message: 'Task is queued');
    }

    final fileId = request.uri.queryParameters['fileId'];
    final token = request.uri.queryParameters['token'];
    final sessionId = request.uri.queryParameters['sessionId'];
    if (fileId == null || token == null || (v2 && sessionId == null)) {
      // reject because of missing parameters
      _logger.warning('Missing parameters: fileId=$fileId, token=$token, sessionId=$sessionId');
      return await request.respondJson(400, message: 'Missing parameters');
    }

    if (v2 && sessionId != receiveState.sessionId) {
      // reject because of wrong session id
      _logger.warning('Wrong session id: $sessionId (expected: ${receiveState.sessionId})');
      return await request.respondJson(403, message: 'Invalid session id');
    }

    final receivingFile = receiveState.files[fileId];
    if (receivingFile == null || receivingFile.token != token) {
      // reject because there is no file or token does not match
      _logger.warning('Wrong fileId: $fileId (expected: ${receivingFile?.file.id})');
      return await request.respondJson(403, message: 'Invalid token');
    }
    if (receivingFile.status == FileStatus.sending || receivingFile.status == FileStatus.finished) {
      return request.respondJson(409, message: 'File already active or finished');
    }

    // begin of actual file transfer
    server.setState(
      (oldState) => oldState?.copyWith(
        session: receiveState.copyWith(
          files: {...receiveState.files}..update(
              fileId,
              (_) => receivingFile.copyWith(
                status: FileStatus.sending,
              ),
            ),
          startTime: receiveState.startTime ?? DateTime.now().millisecondsSinceEpoch,
          status: SessionStatus.sending, // in case it was finishedWithErrors and user retries a failed file
        ),
      ),
    );
    final fileType = receivingFile.file.fileType;
    final saveToGallery = receiveState.saveToGallery && (fileType == FileType.image || fileType == FileType.video);
    final backupItem = backupReceiptCoordinator.itemForSession(
      receiveState.sessionId,
      fileId,
    );

    var receivedBytes = 0;
    final incomingBytes = (bytesOverride ?? request).map((chunk) {
      if (server.getStateOrNull()?.session == null) {
        throw StateError('Task canceled');
      }
      return chunk;
    });
    try {
      final targetFileName = backupItem == null ? receivingFile.desiredName! : backupDestinationFileName(backupItem.snapshotItem);
      final (destinationPath, documentUri, finalName) = backupItem == null && !receiveState.destinationDirectory.startsWith('content://')
          ? (await taskFilePath(receiveState.destinationDirectory, targetFileName), null, p.basename(targetFileName))
          : await digestFilePathAndPrepareDirectory(
              parentDirectory: saveToGallery ? receiveState.cacheDirectory : receiveState.destinationDirectory,
              fileName: _taskFolder == null ? targetFileName : '$_taskFolder/$targetFileName',
              createdDirectories: receiveState.createdDirectories,
            );

      _logger.info('Saving ${receivingFile.file.fileName} to $destinationPath');

      if (backupItem != null) {
        if (saveToGallery || documentUri != null) {
          throw StateError(
            'Native backup receipts require a normal file-system inbox.',
          );
        }
        await backupReceiptCoordinator.markWriting(
          sessionId: receiveState.sessionId,
          fileId: fileId,
          finalPath: destinationPath,
        );
        var streamedBytes = 0;
        final byteStream = incomingBytes.map((chunk) {
          final bytes = chunk;
          streamedBytes += bytes.length;
          if (receivingFile.file.size != 0) {
            server.ref.notifier(progressProvider).setProgress(
                  sessionId: receiveState.sessionId,
                  fileId: fileId,
                  progress: streamedBytes / receivingFile.file.size,
                );
          }
          return bytes;
        });
        final result = await _backupFileWriter.write(
          finalPath: destinationPath,
          bytes: byteStream,
          expectedSize: backupItem.snapshotItem.sizeBytes,
          expectedSha256: backupItem.sha256,
          batchId: backupReceiptCoordinator.batchIdForSession(receiveState.sessionId)!,
          mediaKey: backupItem.snapshotItem.mediaKey,
          beforeCommit: (actualSize, actualSha256) {
            if (server.getStateOrNull()?.session == null) {
              throw StateError('Task canceled');
            }
            return backupReceiptCoordinator
                .markReady(
                  sessionId: receiveState.sessionId,
                  fileId: fileId,
                  actualSizeBytes: actualSize,
                  actualSha256: actualSha256,
                )
                .then((_) => beforePublish?.call(destinationPath));
          },
        );
        final modified = receivingFile.file.metadata?.lastModified;
        if (modified != null) {
          try {
            await File(result.path).setLastModified(modified);
          } on FileSystemException {
            // Timestamp metadata is helpful but not part of byte durability.
          }
        }
        await backupReceiptCoordinator.markVerified(
          sessionId: receiveState.sessionId,
          fileId: fileId,
          actualSizeBytes: result.sizeBytes,
          actualSha256: result.sha256,
        );
      } else if (documentUri == null && !saveToGallery) {
        await _backupFileWriter.write(
            finalPath: destinationPath,
            bytes: incomingBytes.map((chunk) {
              receivedBytes += chunk.length;
              if (receivingFile.file.size > 0) {
                server.ref
                    .notifier(progressProvider)
                    .setProgress(sessionId: receiveState.sessionId, fileId: fileId, progress: receivedBytes / receivingFile.file.size);
              }
              return chunk;
            }),
            expectedSize: receivingFile.file.size,
            batchId: receiveState.sessionId,
            mediaKey: fileId,
            expectedSha256: receivingFile.file.hash,
            beforeCommit: (_, __) async {
              if (server.getStateOrNull()?.session == null) {
                throw StateError('Task canceled');
              }
              await beforePublish?.call(destinationPath);
            });
      } else {
        await saveFile(
          destinationPath: destinationPath,
          documentUri: documentUri,
          name: finalName,
          preserveName: backupItem == null,
          expectedSize: receivingFile.file.size,
          saveToGallery: saveToGallery,
          isImage: fileType == FileType.image,
          stream: incomingBytes,
          androidSdkInt: server.ref.read(deviceInfoProvider).androidSdkInt,
          lastModified: receivingFile.file.metadata?.lastModified,
          lastAccessed: receivingFile.file.metadata?.lastAccessed,
          onProgress: (savedBytes) {
            if (receivingFile.file.size != 0) {
              server.ref.notifier(progressProvider).setProgress(
                    sessionId: receiveState.sessionId,
                    fileId: fileId,
                    progress: savedBytes / receivingFile.file.size,
                  );
            }
          },
        );
      }
      if (server.getState().session == null || !allowedStates.contains(server.getState().session!.status)) {
        return await request.respondJson(500, message: 'Server is in invalid state');
      }
      await onCommitted?.call(destinationPath);
      server.setState(
        (oldState) => oldState?.copyWith(
          session: oldState.session?.fileFinished(
            fileId: fileId,
            status: FileStatus.finished,
            path: saveToGallery ? null : destinationPath,
            savedToGallery: saveToGallery,
            errorMessage: null,
          ),
        ),
      );

      // Track it in history
      await server.ref.redux(receiveHistoryProvider).dispatchAsync(AddHistoryEntryAction(
            entryId: fileId,
            fileName: receivingFile.desiredName!,
            fileType: receivingFile.file.fileType,
            path: saveToGallery ? null : destinationPath,
            savedToGallery: saveToGallery,
            isMessage: false,
            fileSize: receivingFile.file.size,
            senderAlias: receiveState.senderAlias,
            timestamp: DateTime.now().toUtc(),
          ));

      _logger.info('Saved ${receivingFile.file.fileName}.');
    } catch (e, st) {
      if (backupItem != null) {
        try {
          await backupReceiptCoordinator.resetUnverified(
            sessionId: receiveState.sessionId,
            fileId: fileId,
          );
        } catch (resetError, resetStackTrace) {
          _logger.warning(
            'Could not reset an interrupted backup receipt item.',
            resetError,
            resetStackTrace,
          );
        }
      }
      server.setState(
        (oldState) => oldState?.copyWith(
          session: oldState.session?.fileFinished(
            fileId: fileId,
            status: FileStatus.failed,
            path: null,
            savedToGallery: false,
            errorMessage: e.toString(),
          ),
        ),
      );
      _logger.severe('Failed to save file', e, st);
    }

    if (server.getState().session?.files[fileId]?.status == FileStatus.finished) {
      server.ref.notifier(progressProvider).setProgress(
            sessionId: receiveState.sessionId,
            fileId: fileId,
            progress: 1,
          );
    }

    final session = server.getState().session;
    if (session == null) {
      return await request.respondJson(500, message: 'Server is in invalid state');
    }

    if (allowedStates.contains(session.status) && session.files.values.map((e) => e.status).isFinishedOrError) {
      server.ref.notifier(taskProvider).queue.release(session.sessionId);
      _stopForeground();
      final hasError = session.files.values.any((f) => f.status == FileStatus.failed);
      server.setState(
        (oldState) => oldState?.copyWith(
          session: oldState.session!.copyWith(
            status: hasError ? SessionStatus.finishedWithErrors : SessionStatus.finished,
            endTime: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      _logger.info('Received all files.');
    }

    return server.getState().session?.files[fileId]?.status == FileStatus.finished
        ? await request.respondJson(200)
        : await request.respondJson(500, message: 'Could not save file. Check receiving device for more information.');
  }

  Future<void> _cancelHandler({
    required HttpRequest request,
    required bool v2,
  }) async {
    final receiveSession = fixedSessionId == null ? null : server.getState().session;
    if (receiveSession != null) {
      // We are currently receiving files.

      if (!v2 && receiveSession.sender.version != '1.0') {
        // disallow v1 cancel for active v2 sessions
        return await request.respondJson(403, message: 'No permission');
      }

      if (receiveSession.sender.ip != request.ip) {
        return await request.respondJson(403, message: 'No permission');
      }

      // require session id for v2
      // don't require it when during waiting state
      if (v2 && receiveSession.status != SessionStatus.waiting) {
        final sessionId = request.uri.queryParameters['sessionId'];
        if (sessionId != receiveSession.sessionId) {
          return await request.respondJson(403, message: 'No permission');
        }
      }

      // check if valid state
      final currentStatus = receiveSession.status;
      if (currentStatus != SessionStatus.waiting && currentStatus != SessionStatus.sending) {
        return await request.respondJson(403, message: 'No permission');
      }

      final paused = request.uri.queryParameters['ifPaused'] == '1';
      closeSession();
      server.ref.notifier(taskProvider).update(receiveSession.sessionId, paused ? TransferTaskStage.paused : TransferTaskStage.canceled);
      if (!paused) unawaited(_discardResume(receiveSession));
      return await request.respondJson(200);
    } else {
      // We are not receiving files so we may be sending files.

      final sessionId = request.uri.queryParameters['sessionId'];
      final sendSessions = server.ref.read(sendProvider);
      final SendSessionState sendState;
      if (v2) {
        // In v2, we require sessionId.

        final selectedSession = sendSessions.values.firstWhereOrNull((s) => s.remoteSessionId == sessionId);
        if (selectedSession == null) {
          return await request.respondJson(403, message: 'No permission');
        }

        sendState = selectedSession;
      } else {
        // In v1, we are a little bit more tolerant.
        // Let's assume the sessionId if only one send session exist

        final onlySession = sendSessions.values.singleOrNull;
        if (onlySession == null) {
          return await request.respondJson(403, message: 'No permission');
        }

        sendState = onlySession;
      }

      if (sendState.target.ip != request.ip) {
        return await request.respondJson(403, message: 'No permission');
      }

      // check if valid state
      if (sendState.status != SessionStatus.sending) {
        return await request.respondJson(403, message: 'No permission');
      }

      if (request.uri.queryParameters['ifPaused'] == '1') {
        server.ref.notifier(taskProvider).update(sendState.sessionId, TransferTaskStage.paused);
        server.ref.notifier(sendProvider).pauseSession(sendState.sessionId, notifyPeer: false);
      } else {
        server.ref.notifier(sendProvider).cancelSessionByReceiver(sendState.sessionId);
      }
      return await request.respondJson(200);
    }
  }

  Future<void> _showHandler({
    required HttpRequest request,
    required String showToken,
  }) async {
    final senderToken = request.uri.queryParameters['token'];
    if (senderToken == showToken && checkPlatformIsDesktop()) {
      // ignore: unawaited_futures
      showFromTray().catchError((e) {
        // don't wait for it
        _logger.severe('Failed to show from tray', e);
      });

      // ignore: unawaited_futures
      request.readAsString().then((body) async {
        if (body.isEmpty) {
          return;
        }

        final Map<String, dynamic> jsonBody = jsonDecode(body);
        final List<String> args = (jsonBody['args'] as List?)?.cast<String>() ?? <String>[];
        final filesAdded = await server.ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
        if (filesAdded) {
          server.ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
        }
      });

      return await request.respondJson(200);
    }

    return await request.respondJson(403, message: 'Invalid token');
  }

  void acceptFileRequest(Map<String, String> fileNameMap) {
    if (fixedSessionId == null) {
      controllerFor(null)?.acceptFileRequest(fileNameMap);
      return;
    }
    final controller = server.getState().session?.responseHandler;
    if (controller == null || controller.isClosed) {
      return;
    }

    controller.add(fileNameMap);
    controller.close(); // ignore: discarded_futures
  }

  void declineFileRequest() {
    if (fixedSessionId == null) {
      controllerFor(null)?.declineFileRequest();
      return;
    }
    final controller = server.getState().session?.responseHandler;
    if (controller == null || controller.isClosed) {
      return;
    }

    controller.add(null);
    controller.close(); // ignore: discarded_futures
  }

  /// Updates the destination directory for the current session.
  void setSessionDestinationDir(String destinationDirectory) {
    if (fixedSessionId == null) {
      controllerFor(null)?.setSessionDestinationDir(destinationDirectory);
      return;
    }
    server.setState(
      (oldState) => oldState?.copyWith(
        session: oldState.session?.copyWith(
          destinationDirectory: normalizeDestinationDirectory(destinationDirectory),
        ),
      ),
    );
  }

  /// Updates the "saveToGallery" setting for the current session.
  void setSessionSaveToGallery(bool saveToGallery) {
    if (fixedSessionId == null) {
      controllerFor(null)?.setSessionSaveToGallery(saveToGallery);
      return;
    }
    server.setState(
      (oldState) => oldState?.copyWith(
        session: oldState.session?.copyWith(
          saveToGallery: saveToGallery,
        ),
      ),
    );
  }

  /// In addition to [closeSession], this method also
  /// - cancels incoming requests (TODO)
  /// - notifies the sender that the session has been canceled
  void cancelSession() async {
    if (fixedSessionId == null) {
      controllerFor(null)?.cancelSession();
      return;
    }
    final session = server.getStateOrNull()?.session;
    if (session == null) {
      // the server is not running
      return;
    }

    closeSession();
    server.ref.notifier(taskProvider).update(session.sessionId, TransferTaskStage.canceled);
    await _discardResume(session);
    // Notify after local cancellation, which must not wait for the network.
    try {
      await server.ref.read(httpProvider).discovery.post(ApiRoute.cancel.target(session.sender, query: {'sessionId': session.sessionId}));
    } catch (e) {
      _logger.warning('Failed to notify sender', e);
    }

    // TODO: cancel incoming requests (https://github.com/dart-lang/shelf/issues/319)
    // restartServer(alias: tempState.alias, port: tempState.port);
  }

  void closeSession() {
    if (fixedSessionId == null) {
      controllerFor(null)?.closeSession();
      return;
    }
    final sessionId = server.getStateOrNull()?.session?.sessionId;
    if (sessionId == null) {
      return;
    }
    final response = server.getStateOrNull()?.session?.responseHandler;
    if (response != null && !response.isClosed) {
      response.add(null);
      unawaited(response.close());
    }
    server.ref.notifier(taskProvider).queue.release(sessionId);

    server.setState(
      (oldState) => oldState?.copyWith(
        session: null,
      ),
    );
    backupReceiptCoordinator.detachSession(sessionId);
    server.ref.notifier(progressProvider).removeSession(sessionId);
    _stopForeground();
  }

  bool _foregroundActive = false;
  void _stopForeground() {
    if (!_foregroundActive) return;
    _foregroundActive = false;
    unawaited(stopTransferForegroundService());
  }

  String? _taskFolder;
  void interruptAll() {
    for (final entry in _controllers.entries.toList()) {
      final session = server.getStateOrNull()?.sessions[entry.key];
      if (session?.status == SessionStatus.sending || session?.status == SessionStatus.waiting) {
        server.ref.notifier(taskProvider).update(entry.key, TransferTaskStage.interrupted, error: '接收服务已停止，可重新连接后继续');
      }
      entry.value.closeSession();
    }
    _controllers.clear();
  }

  Future<void> _admit(HttpRequest request) async {
    final session = server.getStateOrNull()?.session;
    final token = request.uri.queryParameters['token'];
    if (session == null || request.ip != session.sender.ip || token == null || !session.files.values.any((file) => file.token == token)) {
      return request.respondJson(403, message: 'No permission');
    }
    final tasks = server.ref.notifier(taskProvider);
    if (session.status != SessionStatus.sending && session.status != SessionStatus.finishedWithErrors) {
      return request.respondJson(409, message: 'Task is not ready');
    }
    if (!tasks.queue.isActive(session.sessionId)) {
      final admitted = await tasks.queue.acquire(session.sessionId, media: _isMedia).timeout(const Duration(milliseconds: 1), onTimeout: () => false);
      if (!admitted) {
        tasks.queue.release(session.sessionId);
        tasks.update(session.sessionId, TransferTaskStage.queued);
        return request.respondJson(409, message: 'Receiver queue busy');
      }
    }
    tasks.update(session.sessionId, TransferTaskStage.running);
    return request.respondJson(200);
  }

  Future<void> _resumeHandler(HttpRequest request, {required bool chunk}) async {
    final session = server.getStateOrNull()?.session;
    final query = request.uri.queryParameters;
    final file = session?.files[query['fileId']];
    if (session == null || file == null || session.sender.ip != request.ip || file.token == null || file.token != query['token']) {
      return request.respondJson(403, message: 'No permission');
    }
    if (session.status != SessionStatus.sending && session.status != SessionStatus.finishedWithErrors && session.status != SessionStatus.finished) {
      return request.respondJson(409, message: 'Task is not running');
    }
    final hash = query['sha256'];
    if (chunk && !server.ref.notifier(taskProvider).queue.isActive(session.sessionId)) {
      return request.respondJson(409, message: 'Task is queued');
    }
    if (_transferId == null || hash == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      return request.respondJson(400, message: 'Invalid resume metadata');
    }
    final support = await getApplicationSupportDirectory();
    final store = _resumeStore ??= ResumableFileStore(Directory(p.join(support.path, 'localshare-transfer-data')));
    final key = store.key(session.sender.fingerprint, _transferId!, file.file.id);
    try {
      final status = await store.status(key, file.file.size, hash);
      if (status['committed'] == true) {
        server.setState((old) => old?.copyWith(
            session: old.session?.fileFinished(
                fileId: file.file.id, status: FileStatus.finished, path: status['path'] as String, savedToGallery: false, errorMessage: null)));
        _finishResumedSession();
        return request.respondJson(200, body: status);
      }
      if (!chunk) return request.respondJson(200, body: status);
      final offset = int.tryParse(query['offset'] ?? '');
      if (offset == null) {
        return request.respondJson(400, message: 'Missing offset');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final data in request) {
        if (bytes.length + data.length > transferChunkSize) {
          return request.respondJson(413, message: 'Chunk too large');
        }
        bytes.add(data);
      }
      if (server.getStateOrNull()?.session == null) {
        return request.respondJson(409, message: 'Task canceled');
      }
      final next = await store.append(
          key: key,
          size: file.file.size,
          hash: hash,
          offset: offset,
          bytes: bytes.takeBytes(),
          chunkHash: request.headers.value('x-localshare-chunk-sha256') ?? '');
      server.ref.notifier(taskProvider).checkpoint(session.sessionId, file.file.id, next);
      server.ref
          .notifier(progressProvider)
          .setProgress(sessionId: session.sessionId, fileId: file.file.id, progress: file.file.size == 0 ? 1 : next / file.file.size);
      if (next == file.file.size) {
        await _uploadHandler(
            request: request,
            v2: true,
            bytesOverride: store.dataFile(key).openRead().map((data) => Uint8List.fromList(data)),
            onCommitted: (path) => store.commit(key, file.file.size, hash, path),
            beforePublish: (path) => store.publishing(key, file.file.size, hash, path));
        return;
      }
      return request.respondJson(200, body: {'offset': next});
    } catch (error) {
      return request.respondJson(409, message: error.toString());
    }
  }

  ResumableFileStore? _resumeStore;
  Future<void> _discardResume(ReceiveSessionState session) async {
    if (_transferId == null) return;
    final support = await getApplicationSupportDirectory();
    final store = _resumeStore ??= ResumableFileStore(Directory(p.join(support.path, 'localshare-transfer-data')));
    for (final id in session.files.keys) {
      await store.discard(store.key(session.sender.fingerprint, _transferId!, id));
    }
  }

  void _finishResumedSession() {
    final session = server.getStateOrNull()?.session;
    if (session == null) return;
    if (session.files.values.every((f) => f.status == FileStatus.finished || f.status == FileStatus.skipped)) {
      server.setState(
          (old) => old?.copyWith(session: old.session?.copyWith(status: SessionStatus.finished, endTime: DateTime.now().millisecondsSinceEpoch)));
      server.ref.notifier(taskProvider).queue.release(session.sessionId);
      _stopForeground();
    }
  }
}

String? _validateBackupFileDescriptors({
  required BackupPrepareMetadata metadata,
  required Map<String, FileDto> files,
}) {
  final mappedFileIds = metadata.fileIdToMediaKey.keys.toSet();
  if (mappedFileIds.length != files.length || !mappedFileIds.containsAll(files.keys)) {
    return 'Backup file mapping does not match the upload descriptors.';
  }
  final itemsByKey = <String, BackupManifestItem>{
    for (final item in metadata.manifest.items) item.snapshotItem.mediaKey: item,
  };
  for (final entry in files.entries) {
    final mediaKey = metadata.fileIdToMediaKey[entry.key];
    final item = itemsByKey[mediaKey];
    if (item == null) {
      return 'Backup descriptor references an unknown media item.';
    }
    final media = item.snapshotItem;
    if (entry.value.fileName != '${media.relativePath}${media.displayName}' || entry.value.size != media.sizeBytes) {
      return 'Backup descriptor does not match its manifest item.';
    }
  }
  return null;
}
