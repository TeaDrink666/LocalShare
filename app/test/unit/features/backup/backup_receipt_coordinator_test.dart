import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/protocol/protocol.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_coordinator.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_store.dart';
import 'package:test/test.dart';

void main() {
  group('crash recovery', () {
    late Directory temporaryDirectory;
    late String databasePath;
    BackupReceiptStore? recoveredStore;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'localshare-receipt-recovery-',
      );
      databasePath = _childPath(temporaryDirectory, 'receipts.sqlite');
    });

    tearDown(() async {
      recoveredStore?.close();
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    Future<BackupPlanResponse> restartAndPlan(BackupManifest manifest) async {
      final coordinator = BackupReceiptCoordinator(
        storeOpener: () async {
          final store = BackupReceiptStore.open(databasePath);
          recoveredStore = store;
          return store;
        },
      );
      return coordinator.plan(_prepareMetadata(manifest));
    }

    test('prepared item remains upload-required after restart', () async {
      final manifest = _manifest(size: 4);
      _seedStore(databasePath, (store) {
        store.prepare(manifest, targetFingerprint: _targetFingerprint);
      });

      final plan = await restartAndPlan(manifest);

      expect(plan.requiredMediaKeys, [_mediaKey]);
      expect(plan.committedItems, isEmpty);
      expect(
        recoveredStore!
            .batchItems(BackupBatchKey.fromManifest(manifest))
            .single
            .status,
        BackupReceiptStatus.prepared,
      );
    });

    test('writing item never trusts a file that appeared before restart',
        () async {
      final bytes = <int>[1, 2, 3, 4];
      final manifest = _manifest(size: bytes.length);
      final publishedFile = File(
        _childPath(temporaryDirectory, 'writing.bin'),
      )..writeAsBytesSync(bytes, flush: true);
      _seedStore(databasePath, (store) {
        final batch = BackupBatchKey.fromManifest(manifest);
        store.prepare(manifest, targetFingerprint: _targetFingerprint);
        store.markWriting(
          batch,
          _mediaKey,
          finalPath: publishedFile.path,
        );
      });

      final plan = await restartAndPlan(manifest);

      expect(plan.requiredMediaKeys, [_mediaKey]);
      expect(plan.committedItems, isEmpty);
      final receipt = recoveredStore!
          .batchItems(BackupBatchKey.fromManifest(manifest))
          .single;
      expect(receipt.status, BackupReceiptStatus.prepared);
      expect(receipt.finalPath, isNull);
      expect(receipt.actualSha256, isNull);
      expect(publishedFile.readAsBytesSync(), bytes);
    });

    test('missing writing file stays upload-required and can reuse its path',
        () async {
      final manifest = _manifest(size: 4);
      final missingPath = _childPath(temporaryDirectory, 'missing.bin');
      _seedStore(databasePath, (store) {
        final batch = BackupBatchKey.fromManifest(manifest);
        store.prepare(manifest, targetFingerprint: _targetFingerprint);
        store.markWriting(batch, _mediaKey, finalPath: missingPath);
      });

      final plan = await restartAndPlan(manifest);

      expect(plan.requiredMediaKeys, [_mediaKey]);
      expect(plan.committedItems, isEmpty);
      final receipt = recoveredStore!
          .batchItems(BackupBatchKey.fromManifest(manifest))
          .single;
      expect(receipt.status, BackupReceiptStatus.writing);
      expect(receipt.finalPath, missingPath);
    });

    test('resetUnverified returns an unsigned writing item to prepared',
        () async {
      final manifest = _manifest(size: 4);
      final coordinator = BackupReceiptCoordinator(
        storeOpener: () async {
          final store = BackupReceiptStore.open(databasePath);
          recoveredStore = store;
          return store;
        },
      );
      await coordinator.attachSession(
        sessionId: 'session-writing',
        senderFingerprint: _sourceDevice,
        metadata: _prepareMetadata(manifest),
      );
      await coordinator.markWriting(
        sessionId: 'session-writing',
        fileId: 'file-1',
        finalPath: _childPath(temporaryDirectory, 'failed-writing.bin'),
      );

      await coordinator.resetUnverified(
        sessionId: 'session-writing',
        fileId: 'file-1',
      );

      final receipt = recoveredStore!
          .batchItems(BackupBatchKey.fromManifest(manifest))
          .single;
      expect(receipt.status, BackupReceiptStatus.prepared);
      expect(receipt.finalPath, isNull);
    });

    test('ready item is promoted using its persisted actual hash', () async {
      final bytes = <int>[10, 20, 30, 40];
      final actualHash = sha256.convert(bytes).toString();
      final manifest = _manifest(size: bytes.length);
      final publishedFile = File(
        _childPath(temporaryDirectory, 'ready.bin'),
      )..writeAsBytesSync(bytes, flush: true);
      _seedStore(databasePath, (store) {
        final batch = BackupBatchKey.fromManifest(manifest);
        store.prepare(manifest, targetFingerprint: _targetFingerprint);
        store.markWriting(
          batch,
          _mediaKey,
          finalPath: publishedFile.path,
        );
        store.markReady(
          batch,
          _mediaKey,
          actualSizeBytes: bytes.length,
          actualSha256: actualHash,
        );
      });

      final plan = await restartAndPlan(manifest);

      expect(plan.requiredMediaKeys, isEmpty);
      expect(plan.committedItems.map((item) => item.mediaKey), [_mediaKey]);
      final receipt = recoveredStore!
          .batchItems(BackupBatchKey.fromManifest(manifest))
          .single;
      expect(receipt.status, BackupReceiptStatus.verified);
      expect(receipt.actualSha256, actualHash);
      expect(receipt.verifiedAtUtc, isNotNull);
    });

    test('resetUnverified preserves ready proof for restart recovery',
        () async {
      final bytes = <int>[50, 60, 70, 80];
      final actualHash = sha256.convert(bytes).toString();
      final manifest = _manifest(size: bytes.length);
      final publishedFile = File(
        _childPath(temporaryDirectory, 'ready-after-error.bin'),
      )..writeAsBytesSync(bytes, flush: true);
      final coordinator = BackupReceiptCoordinator(
        storeOpener: () async {
          final store = BackupReceiptStore.open(databasePath);
          recoveredStore = store;
          return store;
        },
      );
      await coordinator.attachSession(
        sessionId: 'session-ready',
        senderFingerprint: _sourceDevice,
        metadata: _prepareMetadata(manifest),
      );
      await coordinator.markWriting(
        sessionId: 'session-ready',
        fileId: 'file-1',
        finalPath: publishedFile.path,
      );
      await coordinator.markReady(
        sessionId: 'session-ready',
        fileId: 'file-1',
        actualSizeBytes: bytes.length,
        actualSha256: actualHash,
      );

      await coordinator.resetUnverified(
        sessionId: 'session-ready',
        fileId: 'file-1',
      );

      final batch = BackupBatchKey.fromManifest(manifest);
      expect(
        recoveredStore!.batchItems(batch).single.status,
        BackupReceiptStatus.ready,
      );
      recoveredStore!.close();
      recoveredStore = null;

      final plan = await restartAndPlan(manifest);

      expect(plan.requiredMediaKeys, isEmpty);
      expect(plan.committedItems.map((item) => item.mediaKey), [_mediaKey]);
      expect(
        recoveredStore!.batchItems(batch).single.status,
        BackupReceiptStatus.verified,
      );
    });

    test('ready item rejects unrelated content with the same byte length',
        () async {
      final receivedBytes = <int>[1, 1, 1, 1];
      final unrelatedBytes = <int>[2, 2, 2, 2];
      final persistedHash = sha256.convert(receivedBytes).toString();
      final manifest = _manifest(size: receivedBytes.length);
      final publishedFile = File(
        _childPath(temporaryDirectory, 'replaced-ready.bin'),
      );
      _seedStore(databasePath, (store) {
        final batch = BackupBatchKey.fromManifest(manifest);
        store.prepare(manifest, targetFingerprint: _targetFingerprint);
        store.markWriting(
          batch,
          _mediaKey,
          finalPath: publishedFile.path,
        );
        store.markReady(
          batch,
          _mediaKey,
          actualSizeBytes: receivedBytes.length,
          actualSha256: persistedHash,
        );
      });
      publishedFile.writeAsBytesSync(unrelatedBytes, flush: true);
      expect(publishedFile.lengthSync(), receivedBytes.length);

      final plan = await restartAndPlan(manifest);

      expect(plan.requiredMediaKeys, [_mediaKey]);
      expect(plan.committedItems, isEmpty);
      final receipt = recoveredStore!
          .batchItems(BackupBatchKey.fromManifest(manifest))
          .single;
      expect(receipt.status, BackupReceiptStatus.prepared);
      expect(receipt.actualSha256, isNull);
      expect(publishedFile.readAsBytesSync(), unrelatedBytes);
    });

    test('verified receipt remains committed after its file is moved',
        () async {
      final bytes = <int>[7, 8, 9, 10];
      final actualHash = sha256.convert(bytes).toString();
      final manifest = _manifest(size: bytes.length);
      final originalFile = File(
        _childPath(temporaryDirectory, 'verified.bin'),
      )..writeAsBytesSync(bytes, flush: true);
      _seedStore(databasePath, (store) {
        final batch = BackupBatchKey.fromManifest(manifest);
        store.prepare(manifest, targetFingerprint: _targetFingerprint);
        store.markWriting(
          batch,
          _mediaKey,
          finalPath: originalFile.path,
        );
        store.markVerified(
          batch,
          _mediaKey,
          actualSizeBytes: bytes.length,
          actualSha256: actualHash,
          verifiedAtUtc: DateTime.utc(2026, 7, 13, 10),
        );
      });
      final movedFile = await originalFile.rename(
        _childPath(temporaryDirectory, 'user-library.bin'),
      );

      final plan = await restartAndPlan(manifest);

      expect(await originalFile.exists(), isFalse);
      expect(await movedFile.readAsBytes(), bytes);
      expect(plan.requiredMediaKeys, isEmpty);
      expect(plan.committedItems.map((item) => item.mediaKey), [_mediaKey]);
      expect(
        recoveredStore!
            .batchItems(BackupBatchKey.fromManifest(manifest))
            .single
            .status,
        BackupReceiptStatus.verified,
      );
    });
  });
}

const _mediaKey = 'media:1';
const _targetFingerprint = 'windows-cert-a';
const _sourceDevice = 'android-phone';

BackupPrepareMetadata _prepareMetadata(BackupManifest manifest) {
  return BackupPrepareMetadata(
    manifest: manifest,
    fileIdToMediaKey: const {'file-1': _mediaKey},
    targetFingerprint: _targetFingerprint,
  );
}

BackupManifest _manifest({required int size}) {
  return BackupManifest(
    batchId: 'batch-2026-07-13',
    profileId: 'home-windows',
    sourceDevice: _sourceDevice,
    createdAtUtc: DateTime.utc(2026, 7, 13, 7, 30),
    items: [
      BackupManifestItem(
        snapshotItem: MediaSnapshotItem(
          mediaKey: _mediaKey,
          relativePath: 'DCIM/Camera/',
          displayName: 'IMG_0001.jpg',
          sizeBytes: size,
          modifiedAtSeconds: 1783926000,
          generationModified: 42,
          mimeType: 'image/jpeg',
        ),
      ),
    ],
  );
}

void _seedStore(
  String databasePath,
  void Function(BackupReceiptStore store) seed,
) {
  final store = BackupReceiptStore.open(databasePath);
  try {
    seed(store);
  } finally {
    store.close();
  }
}

String _childPath(Directory directory, String name) {
  return '${directory.path}${Platform.pathSeparator}$name';
}
