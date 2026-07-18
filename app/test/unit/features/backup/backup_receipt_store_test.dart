import 'dart:io';

import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_store.dart';
import 'package:test/test.dart';

void main() {
  late BackupReceiptStore store;

  setUp(() {
    store = BackupReceiptStore.memory();
  });

  tearDown(() {
    store.close();
  });

  group('prepare', () {
    test('transactionally merges manifest subsets and is idempotent', () {
      final manifest = _manifest(items: [
        _item(key: 'media:1', name: 'IMG_0001.jpg'),
        _item(key: 'media:2', name: 'IMG_0002.jpg'),
      ]);

      store.prepare(
        manifest,
        targetFingerprint: 'windows-cert-a',
        items: [manifest.items.first],
      );
      store.prepare(
        manifest,
        targetFingerprint: 'windows-cert-a',
        items: [manifest.items.last],
      );
      store.prepare(
        manifest,
        targetFingerprint: 'windows-cert-a',
        items: manifest.items,
      );

      final receipts = store.batchItems(BackupBatchKey.fromManifest(manifest));
      expect(receipts.map((item) => item.mediaKey), ['media:1', 'media:2']);
      expect(
        receipts.map((item) => item.status),
        everyElement(BackupReceiptStatus.prepared),
      );
    });

    test('rejects a reused batch on another target fingerprint', () {
      final manifest = _manifest();
      store.prepare(manifest, targetFingerprint: 'windows-cert-a');

      expect(
        () => store.prepare(
          manifest,
          targetFingerprint: 'windows-cert-b',
        ),
        throwsA(isA<BackupReceiptConflict>()),
      );
    });

    test('rejects conflicting media metadata and rolls back whole subset', () {
      final original = _manifest(items: [
        _item(key: 'media:1', name: 'IMG_0001.jpg'),
        _item(key: 'media:2', name: 'IMG_0002.jpg'),
      ]);
      store.prepare(
        original,
        targetFingerprint: 'windows-cert-a',
        items: [original.items.last],
      );

      final conflicting = _manifest(items: [
        _item(key: 'media:1', name: 'IMG_0001.jpg'),
        _item(key: 'media:2', name: 'RENAMED_0002.jpg'),
      ]);

      expect(
        () => store.prepare(
          conflicting,
          targetFingerprint: 'windows-cert-a',
          items: conflicting.items,
        ),
        throwsA(
          isA<BackupReceiptConflict>().having(
            (error) => error.message,
            'message',
            contains('different metadata'),
          ),
        ),
      );
      expect(
        store
            .batchItems(BackupBatchKey.fromManifest(original))
            .map((item) => item.mediaKey),
        ['media:2'],
        reason: 'media:1 was inserted before the conflict and must roll back',
      );
    });

    test('requires subset items to belong to the supplied manifest', () {
      final manifest = _manifest();

      expect(
        () => store.prepare(
          manifest,
          targetFingerprint: 'windows-cert-a',
          items: [_item(key: 'not-in-manifest')],
        ),
        throwsArgumentError,
      );
      expect(
        store.batchItems(BackupBatchKey.fromManifest(manifest)),
        isEmpty,
      );
    });

    test('accepts the remaining manifest after a partial phone confirmation',
        () {
      final full = _manifest(items: [
        _item(key: 'media:1', name: 'IMG_0001.jpg'),
        _item(key: 'media:2', name: 'IMG_0002.jpg'),
      ]);
      final batch = BackupBatchKey.fromManifest(full);
      store.prepare(full, targetFingerprint: 'windows-cert-a');
      store.markWriting(batch, 'media:1', finalPath: r'D:\Inbox\one.jpg');
      store.markVerified(
        batch,
        'media:1',
        actualSizeBytes: 100,
        actualSha256: null,
        verifiedAtUtc: DateTime.utc(2026, 7, 13),
      );

      final remaining = _manifest(items: [full.items.last]);
      expect(
        () => store.prepare(
          remaining,
          targetFingerprint: 'windows-cert-a',
        ),
        returnsNormally,
      );

      final confirmedSubset = _manifest(items: [full.items.first]);
      expect(
        store.verifiedMediaKeysMatching(
          confirmedSubset,
          targetFingerprint: 'windows-cert-a',
        ),
        {'media:1'},
      );
    });
  });

  group('writing and verification', () {
    test('exposes interrupted writing data needed for startup recovery', () {
      final manifest = _manifest(
        items: [_item(key: 'media:video', size: 4096, sha256: 'a' * 64)],
      );
      final batch = BackupBatchKey.fromManifest(manifest);
      store.prepare(manifest, targetFingerprint: 'windows-cert-a');

      store.markWriting(
        batch,
        'media:video',
        finalPath: r'D:\BackupInbox\DCIM\VID_0001.mp4',
      );

      final writing = store.writingItems().single;
      expect(writing.batch, batch);
      expect(writing.status, BackupReceiptStatus.writing);
      expect(writing.expectedSizeBytes, 4096);
      expect(writing.expectedSha256, 'a' * 64);
      expect(writing.relativePath, 'DCIM/Camera/');
      expect(writing.finalPath, r'D:\BackupInbox\DCIM\VID_0001.mp4');
      expect(writing.actualSizeBytes, isNull);
      expect(writing.verifiedAtUtc, isNull);
    });

    test('rejects a wrong actual size or expected hash', () {
      final manifest = _manifest(
        items: [_item(key: 'media:1', size: 123, sha256: 'a' * 64)],
      );
      final batch = BackupBatchKey.fromManifest(manifest);
      store.prepare(manifest, targetFingerprint: 'windows-cert-a');
      store.markWriting(batch, 'media:1', finalPath: r'D:\Inbox\one.jpg');

      expect(
        () => store.markVerified(
          batch,
          'media:1',
          actualSizeBytes: 122,
          actualSha256: 'a' * 64,
          verifiedAtUtc: DateTime.utc(2026, 7, 13, 8),
        ),
        throwsA(isA<BackupReceiptVerificationException>()),
      );
      expect(
        () => store.markVerified(
          batch,
          'media:1',
          actualSizeBytes: 123,
          actualSha256: 'b' * 64,
          verifiedAtUtc: DateTime.utc(2026, 7, 13, 8),
        ),
        throwsA(isA<BackupReceiptVerificationException>()),
      );
      expect(store.writingItems(), hasLength(1));
    });

    test('verified receipt is idempotent and never rechecks final path', () {
      final manifest = _manifest(
        items: [_item(key: 'media:1', size: 123, sha256: 'a' * 64)],
      );
      final batch = BackupBatchKey.fromManifest(manifest);
      final verifiedAt = DateTime.utc(2026, 7, 13, 8, 30);
      store.prepare(manifest, targetFingerprint: 'windows-cert-a');
      store.markWriting(
        batch,
        'media:1',
        finalPath: r'Z:\path-that-does-not-exist\IMG_0001.jpg',
      );

      store.markVerified(
        batch,
        'media:1',
        actualSizeBytes: 123,
        actualSha256: 'a' * 64,
        verifiedAtUtc: verifiedAt,
      );
      store.markVerified(
        batch,
        'media:1',
        actualSizeBytes: 123,
        actualSha256: 'a' * 64,
        verifiedAtUtc: verifiedAt.add(const Duration(hours: 1)),
      );

      final matches = store.verifiedItemsMatching(
        manifest,
        targetFingerprint: 'windows-cert-a',
      );
      expect(matches, hasLength(1));
      expect(matches.single.status, BackupReceiptStatus.verified);
      expect(matches.single.verifiedAtUtc, verifiedAt);
      expect(
        matches.single.finalPath,
        r'Z:\path-that-does-not-exist\IMG_0001.jpg',
      );
      expect(store.writingItems(), isEmpty);
    });

    test('requires writing state before verification', () {
      final manifest = _manifest();
      final batch = BackupBatchKey.fromManifest(manifest);
      store.prepare(manifest, targetFingerprint: 'windows-cert-a');

      expect(
        () => store.markVerified(
          batch,
          'media:1',
          actualSizeBytes: 100,
          actualSha256: null,
          verifiedAtUtc: DateTime.utc(2026, 7, 13),
        ),
        throwsA(isA<BackupReceiptStateException>()),
      );
    });
  });

  group('verified manifest matching', () {
    test('matches every item metadata field and the target fingerprint', () {
      final manifest = _manifest();
      final batch = BackupBatchKey.fromManifest(manifest);
      store.prepare(manifest, targetFingerprint: 'windows-cert-a');
      store.markWriting(batch, 'media:1', finalPath: r'D:\Inbox\one.jpg');
      store.markVerified(
        batch,
        'media:1',
        actualSizeBytes: 100,
        actualSha256: null,
        verifiedAtUtc: DateTime.utc(2026, 7, 13),
      );

      expect(
        store.verifiedMediaKeysMatching(
          manifest,
          targetFingerprint: 'windows-cert-a',
        ),
        {'media:1'},
      );
      expect(
        store.verifiedMediaKeysMatching(
          manifest,
          targetFingerprint: 'windows-cert-b',
        ),
        isEmpty,
      );

      final changedMetadata = _manifest(
        items: [_item(key: 'media:1', name: 'RENAMED.jpg')],
      );
      expect(
        store.verifiedMediaKeysMatching(
          changedMetadata,
          targetFingerprint: 'windows-cert-a',
        ),
        isEmpty,
      );
    });
  });

  test('file-backed receipts survive close and reopen', () {
    final directory = Directory.systemTemp.createTempSync(
      'localshare-receipts-',
    );
    final path = '${directory.path}${Platform.pathSeparator}receipts.sqlite';
    final manifest = _manifest();
    final batch = BackupBatchKey.fromManifest(manifest);

    final first = BackupReceiptStore.open(path);
    first.prepare(manifest, targetFingerprint: 'windows-cert-a');
    first.markWriting(batch, 'media:1', finalPath: r'D:\Inbox\one.jpg');
    first.markVerified(
      batch,
      'media:1',
      actualSizeBytes: 100,
      actualSha256: null,
      verifiedAtUtc: DateTime.utc(2026, 7, 13),
    );
    first.close();

    final reopened = BackupReceiptStore.open(path);
    addTearDown(() {
      reopened.close();
      directory.deleteSync(recursive: true);
    });
    expect(
      reopened.verifiedMediaKeysMatching(
        manifest,
        targetFingerprint: 'windows-cert-a',
      ),
      {'media:1'},
    );
  });

  test('close is idempotent and later operations fail clearly', () {
    store.close();
    store.close();

    expect(
      () => store.prepare(
        _manifest(),
        targetFingerprint: 'windows-cert-a',
      ),
      throwsStateError,
    );
  });
}

BackupManifest _manifest({Iterable<BackupManifestItem>? items}) {
  return BackupManifest(
    batchId: 'batch-2026-07-13',
    profileId: 'home-windows',
    sourceDevice: 'android-phone',
    createdAtUtc: DateTime.utc(2026, 7, 13, 7, 30),
    items: items ?? [_item(key: 'media:1')],
  );
}

BackupManifestItem _item({
  required String key,
  String name = 'IMG_0001.jpg',
  int size = 100,
  String? sha256,
}) {
  return BackupManifestItem(
    snapshotItem: MediaSnapshotItem(
      mediaKey: key,
      relativePath: 'DCIM/Camera/',
      displayName: name,
      sizeBytes: size,
      modifiedAtSeconds: 1783926000,
      generationModified: 42,
      mimeType: name.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg',
    ),
    sha256: sha256,
  );
}
