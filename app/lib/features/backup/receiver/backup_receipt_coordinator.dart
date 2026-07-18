import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/protocol/protocol.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef BackupReceiptStoreOpener = Future<BackupReceiptStore> Function();

/// Connects active LocalSend receive sessions to the durable backup ledger.
///
/// Active file/token mappings live only for the duration of a receive session.
/// Verified receipts live in SQLite and therefore survive navigation, process
/// restarts, response loss, and later user moves out of the backup inbox.
final class BackupReceiptCoordinator {
  BackupReceiptCoordinator({
    BackupReceiptStoreOpener storeOpener = _openDefaultStore,
  }) : _storeOpener = storeOpener;

  final BackupReceiptStoreOpener _storeOpener;
  Future<BackupReceiptStore>? _storeFuture;
  final Map<String, _ActiveBackupSession> _sessions = {};

  Future<BackupReceiptStore> get _store => _storeFuture ??= _storeOpener();

  /// Persists a plan and reports which exact items still require upload.
  Future<BackupPlanResponse> plan(BackupPrepareMetadata metadata) async {
    final store = await _store;
    await _recoverWriting(
      store,
      BackupBatchKey.fromManifest(metadata.manifest),
    );
    final committed = _committedItems(store, metadata.manifest,
        targetFingerprint: metadata.targetFingerprint);
    final committedKeys = committed.map((item) => item.mediaKey).toSet();
    return BackupPlanResponse(
      reference: metadata.reference,
      requiredMediaKeys: metadata.manifest.items
          .map((item) => item.snapshotItem.mediaKey)
          .where((mediaKey) => !committedKeys.contains(mediaKey)),
      committedItems: committed,
    );
  }

  /// Associates a validated prepare-upload request with its LocalSend session.
  Future<Set<String>> attachSession({
    required String sessionId,
    required String senderFingerprint,
    required BackupPrepareMetadata metadata,
  }) async {
    if (senderFingerprint != metadata.manifest.sourceDevice) {
      throw const FormatException(
        'Backup sourceDevice does not match the sending device fingerprint.',
      );
    }
    final itemsByKey = <String, BackupManifestItem>{
      for (final item in metadata.manifest.items)
        item.snapshotItem.mediaKey: item,
    };
    final itemsByFileId = <String, BackupManifestItem>{
      for (final entry in metadata.fileIdToMediaKey.entries)
        entry.key: itemsByKey[entry.value]!,
    };

    final store = await _store;
    store.prepare(
      metadata.manifest,
      targetFingerprint: metadata.targetFingerprint,
    );
    await _recoverWriting(
      store,
      BackupBatchKey.fromManifest(metadata.manifest),
    );
    final verified = store.verifiedMediaKeysMatching(
      metadata.manifest,
      targetFingerprint: metadata.targetFingerprint,
    );
    _sessions[sessionId] = _ActiveBackupSession(
      metadata: metadata,
      itemsByFileId: itemsByFileId,
    );
    return verified;
  }

  BackupManifestItem? itemForSession(String sessionId, String fileId) {
    return _sessions[sessionId]?.itemsByFileId[fileId];
  }

  String? batchIdForSession(String sessionId) {
    return _sessions[sessionId]?.metadata.manifest.batchId;
  }

  Future<void> markWriting({
    required String sessionId,
    required String fileId,
    required String finalPath,
  }) async {
    final active = _requireActiveItem(sessionId, fileId);
    final store = await _store;
    store.markWriting(
      BackupBatchKey.fromManifest(active.session.metadata.manifest),
      active.item.snapshotItem.mediaKey,
      finalPath: finalPath,
    );
  }

  Future<void> markVerified({
    required String sessionId,
    required String fileId,
    required int actualSizeBytes,
    required String actualSha256,
  }) async {
    final active = _requireActiveItem(sessionId, fileId);
    final store = await _store;
    store.markVerified(
      BackupBatchKey.fromManifest(active.session.metadata.manifest),
      active.item.snapshotItem.mediaKey,
      actualSizeBytes: actualSizeBytes,
      actualSha256: actualSha256,
      verifiedAtUtc: DateTime.now().toUtc(),
    );
  }

  Future<void> markReady({
    required String sessionId,
    required String fileId,
    required int actualSizeBytes,
    required String actualSha256,
  }) async {
    final active = _requireActiveItem(sessionId, fileId);
    final store = await _store;
    store.markReady(
      BackupBatchKey.fromManifest(active.session.metadata.manifest),
      active.item.snapshotItem.mediaKey,
      actualSizeBytes: actualSizeBytes,
      actualSha256: actualSha256,
    );
  }

  Future<void> resetUnverified({
    required String sessionId,
    required String fileId,
  }) async {
    final active = _requireActiveItem(sessionId, fileId);
    final store = await _store;
    final batch = BackupBatchKey.fromManifest(active.session.metadata.manifest);
    final receipt = store
        .batchItems(batch)
        .where((item) => item.mediaKey == active.item.snapshotItem.mediaKey)
        .single;
    if (receipt.status == BackupReceiptStatus.writing) {
      store.resetWriting(batch, receipt.mediaKey);
    }
    // A ready row already contains the durable hash calculated before the
    // atomic rename. A later error may have happened after that rename but
    // before markVerified, so keep the row for restart recovery instead of
    // discarding the only proof that the published file belongs to this item.
  }

  Future<BackupCommitResponse> commit(BackupManifestMetadata metadata) async {
    final committed = await _queryCommitted(metadata);
    return BackupCommitResponse(
      reference: metadata.reference,
      committedItems: committed,
    );
  }

  Future<BackupReceiptResponse> receipt(
    BackupManifestMetadata metadata,
  ) async {
    final committed = await _queryCommitted(metadata);
    return BackupReceiptResponse(
      reference: metadata.reference,
      committedItems: committed,
    );
  }

  Future<BackupCancelResponse> cancel(BackupBatchReference reference) async {
    _sessions.removeWhere((_, session) {
      final current = session.metadata.reference;
      return current.batchId == reference.batchId &&
          current.profileId == reference.profileId &&
          current.sourceDevice == reference.sourceDevice &&
          current.targetFingerprint == reference.targetFingerprint;
    });
    return BackupCancelResponse(
      reference: reference,
      canceledAtUtc: DateTime.now().toUtc(),
    );
  }

  void detachSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  Future<List<BackupCommittedItem>> _queryCommitted(
    BackupManifestMetadata metadata,
  ) async {
    final store = await _store;
    await _recoverWriting(
      store,
      BackupBatchKey.fromManifest(metadata.manifest),
    );
    return _committedItems(
      store,
      metadata.manifest,
      targetFingerprint: metadata.targetFingerprint,
    );
  }

  List<BackupCommittedItem> _committedItems(
    BackupReceiptStore store,
    BackupManifest manifest, {
    required String targetFingerprint,
  }) {
    return store
        .verifiedItemsMatching(
          manifest,
          targetFingerprint: targetFingerprint,
        )
        .map(
          (receipt) => BackupCommittedItem(
            mediaKey: receipt.mediaKey,
            relativePath: receipt.relativePath,
            displayName: receipt.displayName,
            sizeBytes: receipt.expectedSizeBytes,
            modifiedAtSeconds: receipt.modifiedAtSeconds,
            generationModified: receipt.generationModified,
            // The protocol proves the sender-declared signature. The actual
            // receiver hash is retained in SQLite for diagnostics; when the
            // manifest did not declare a hash, returning it here would not
            // match the current manifest and must therefore remain null.
            sha256: receipt.expectedSha256,
            verifiedAtUtc: receipt.verifiedAtUtc!,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _recoverWriting(
    BackupReceiptStore store,
    BackupBatchKey batch,
  ) async {
    for (final item in store.interruptedItems(batch: batch)) {
      final finalPath = item.finalPath!;
      final type = await FileSystemEntity.type(finalPath, followLinks: false);
      if (item.status == BackupReceiptStatus.writing) {
        if (type == FileSystemEntityType.notFound) {
          // The deterministic path can be reused by the next upload attempt.
          continue;
        }
        // A writing row has no content signature yet, so an entity appearing
        // at the path cannot safely be attributed to LocalShare.
        store.resetWriting(batch, item.mediaKey);
        continue;
      }
      if (type != FileSystemEntityType.file) {
        store.resetWriting(batch, item.mediaKey);
        continue;
      }

      final file = File(finalPath);
      int actualSize;
      try {
        actualSize = await file.length();
      } on FileSystemException {
        continue;
      }
      if (actualSize != item.expectedSizeBytes) {
        store.resetWriting(batch, item.mediaKey);
        continue;
      }

      final actualSha256 =
          (await sha256.bind(file.openRead()).first).toString();
      if (actualSha256 != item.actualSha256) {
        store.resetWriting(batch, item.mediaKey);
        continue;
      }
      store.markVerified(
        batch,
        item.mediaKey,
        actualSizeBytes: actualSize,
        actualSha256: actualSha256,
        verifiedAtUtc: DateTime.now().toUtc(),
      );
    }
  }

  _ActiveItem _requireActiveItem(String sessionId, String fileId) {
    final session = _sessions[sessionId];
    final item = session?.itemsByFileId[fileId];
    if (session == null || item == null) {
      throw StateError('No active backup item for session/file.');
    }
    return _ActiveItem(session: session, item: item);
  }
}

final class _ActiveBackupSession {
  const _ActiveBackupSession({
    required this.metadata,
    required this.itemsByFileId,
  });

  final BackupPrepareMetadata metadata;
  final Map<String, BackupManifestItem> itemsByFileId;
}

final class _ActiveItem {
  const _ActiveItem({required this.session, required this.item});

  final _ActiveBackupSession session;
  final BackupManifestItem item;
}

Future<BackupReceiptStore> _openDefaultStore() async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(
    p.join(support.path, 'localshare', 'backup-receipts'),
  );
  await directory.create(recursive: true);
  return BackupReceiptStore.open(
    p.join(directory.path, 'receipts.sqlite'),
  );
}
