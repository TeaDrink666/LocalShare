import 'dart:convert';

import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/manifest.dart';
import 'package:test/test.dart';

void main() {
  const codec = BackupManifestCodec();

  group('BackupManifest', () {
    test('round trips all persisted fields and derived totals', () {
      final original = _manifest(
        items: [
          _item(
            key: 'external:2',
            name: 'VID_0002.mp4',
            size: 880,
            sha256: 'a' * 64,
          ),
          _item(key: 'external:1', name: 'IMG_0001.jpg', size: 120),
        ],
      );

      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded);

      expect(codec.encode(decoded), encoded);
      expect(decoded.schemaVersion, 1);
      expect(decoded.batchId, 'batch-2026-07-12');
      expect(decoded.profileId, 'home-pc');
      expect(decoded.sourceDevice, 'pixel-9');
      expect(decoded.createdAtUtc, DateTime.utc(2026, 7, 12, 3, 4, 5));
      expect(decoded.itemCount, 2);
      expect(decoded.totalBytes, 1000);
      expect(
        decoded.items.map((item) => item.snapshotItem.mediaKey),
        ['external:1', 'external:2'],
      );
      expect(decoded.items.first.sha256, isNull);
      expect(decoded.items.last.sha256, 'a' * 64);
      expect(() => decoded.items.clear(), throwsUnsupportedError);
    });

    test('encodes equivalent item sets to identical canonical JSON', () {
      final first = _manifest(items: [
        _item(key: 'key-z', path: 'Pictures/', name: 'z.jpg'),
        _item(key: 'key-b', path: 'DCIM/', name: 'b.jpg'),
        _item(key: 'key-a', path: 'DCIM/', name: 'a.jpg'),
      ]);
      final second = _manifest(items: first.items.reversed);

      final firstJson = codec.encode(first);
      final secondJson = codec.encode(second);

      expect(secondJson, firstJson);
      expect(
        first.items.map((item) => item.snapshotItem.mediaKey),
        ['key-a', 'key-b', 'key-z'],
      );
      expect(
        firstJson,
        startsWith(
          '{"batchId":"batch-2026-07-12","createdAtUtc":',
        ),
      );
    });

    test('preserves Unicode paths, names, IDs, and device labels', () {
      final original = BackupManifest(
        batchId: '批次-夏天🌻',
        profileId: '家里的电脑🖥️',
        sourceDevice: '我的手机📱',
        createdAtUtc: DateTime.utc(2026, 7, 12),
        items: [
          _item(
            key: '外部存储:照片-一',
            path: '相机/旅行/',
            name: '夏天🌻.jpg',
          ),
          _item(
            key: '外部ストレージ:写真-二',
            path: 'カメラ/旅行/',
            name: '夏休み🎐.jpg',
          ),
        ],
      );

      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded);

      expect(encoded, contains('夏天🌻.jpg'));
      expect(decoded.batchId, original.batchId);
      expect(decoded.profileId, original.profileId);
      expect(decoded.sourceDevice, original.sourceDevice);
      expect(
        decoded.items.map((item) => item.snapshotItem.displayName),
        ['夏休み🎐.jpg', '夏天🌻.jpg'],
      );
    });

    test('persists metadata only, including null SHA-256 placeholder', () {
      final document = jsonDecode(codec.encode(_manifest())) as Map;
      final item = (document['items'] as List).single as Map;

      expect(item['sha256'], isNull);
      expect(item, isNot(contains('contentUri')));
      expect(item, isNot(contains('representation')));
      expect(item.keys, {
        'displayName',
        'generationModified',
        'mediaKey',
        'mimeType',
        'modifiedAtSeconds',
        'relativePath',
        'sha256',
        'sizeBytes',
      });
    });

    test('rejects local creation timestamps before encoding', () {
      expect(
        () => BackupManifest(
          batchId: 'batch',
          profileId: 'profile',
          sourceDevice: 'phone',
          createdAtUtc: DateTime(2026, 7, 12),
          items: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('BackupManifestCodec validation', () {
    test('rejects unsupported schema versions', () {
      final document = _document();
      document['schemaVersion'] = 2;

      expect(
        () => codec.decode(jsonEncode(document)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate media keys', () {
      final document = _document();
      final item = Map<String, Object?>.from(
        (document['items'] as List).single as Map,
      );
      document['items'] = [item, Map<String, Object?>.from(item)];
      document['itemCount'] = 2;
      document['totalBytes'] = 200;

      expect(
        () => codec.decode(jsonEncode(document)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate mediaKey'),
          ),
        ),
      );
    });

    test('rejects duplicate destination paths', () {
      final document = _document();
      final first = Map<String, Object?>.from(
        (document['items'] as List).single as Map,
      );
      final second = Map<String, Object?>.from(first)
        ..['mediaKey'] = 'external:different';
      document['items'] = [first, second];
      document['itemCount'] = 2;
      document['totalBytes'] = 200;

      expect(
        () => codec.decode(jsonEncode(document)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate destination path'),
          ),
        ),
      );
    });

    test('rejects mismatched item and byte totals', () {
      final wrongCount = _document()..['itemCount'] = 9;
      final wrongBytes = _document()..['totalBytes'] = 99;

      expect(
        () => codec.decode(jsonEncode(wrongCount)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(r'$.itemCount does not match'),
          ),
        ),
      );
      expect(
        () => codec.decode(jsonEncode(wrongBytes)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(r'$.totalBytes does not match'),
          ),
        ),
      );
    });

    test('rejects negative sizes and totals', () {
      final negativeItem = _document();
      ((negativeItem['items'] as List).single as Map)['sizeBytes'] = -1;
      negativeItem['totalBytes'] = -1;
      final negativeTotal = _document()..['totalBytes'] = -1;

      expect(
        () => codec.decode(jsonEncode(negativeItem)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => codec.decode(jsonEncode(negativeTotal)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects absolute, traversing, and non-normalized paths', () {
      for (final invalidPath in [
        '/DCIM/Camera/',
        r'C:/DCIM/Camera/',
        '../Camera/',
        'DCIM/../Camera/',
        'DCIM//Camera/',
        r'DCIM\Camera\',
        'DCIM/Camera',
      ]) {
        final document = _document();
        ((document['items'] as List).single as Map)['relativePath'] =
            invalidPath;

        expect(
          () => codec.decode(jsonEncode(document)),
          throwsA(isA<FormatException>()),
          reason: 'Expected path to be rejected: $invalidPath',
        );
      }
    });

    test('rejects empty keys and duplicate or unsafe file names', () {
      for (final invalidKey in ['', '   ', 'key\u0000']) {
        final document = _document();
        ((document['items'] as List).single as Map)['mediaKey'] = invalidKey;

        expect(
          () => codec.decode(jsonEncode(document)),
          throwsA(isA<FormatException>()),
          reason: 'Expected key to be rejected: $invalidKey',
        );
      }

      for (final invalidName in ['', '..', 'nested/file.jpg', r'nested\file']) {
        final document = _document();
        ((document['items'] as List).single as Map)['displayName'] =
            invalidName;

        expect(
          () => codec.decode(jsonEncode(document)),
          throwsA(isA<FormatException>()),
          reason: 'Expected name to be rejected: $invalidName',
        );
      }
    });

    test('rejects timestamps without the UTC Z designator', () {
      for (final timestamp in [
        '2026-07-12T03:04:05',
        '2026-07-12T11:04:05+08:00',
        'not-a-date',
      ]) {
        final document = _document()..['createdAtUtc'] = timestamp;

        expect(
          () => codec.decode(jsonEncode(document)),
          throwsA(isA<FormatException>()),
          reason: 'Expected timestamp to be rejected: $timestamp',
        );
      }
    });

    test('rejects missing and unexpected fields, including content URI', () {
      final missing = _document()..remove('profileId');
      final unexpected = _document()..['extra'] = true;
      final contentUri = _document();
      ((contentUri['items'] as List).single as Map)['contentUri'] =
          'content://media/external/images/1';

      for (final document in [missing, unexpected, contentUri]) {
        expect(
          () => codec.decode(jsonEncode(document)),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects malformed SHA-256 values', () {
      for (final digest in ['abc', 'A' * 64, 'g' * 64]) {
        final document = _document();
        ((document['items'] as List).single as Map)['sha256'] = digest;

        expect(
          () => codec.decode(jsonEncode(document)),
          throwsA(isA<FormatException>()),
          reason: 'Expected digest to be rejected: $digest',
        );
      }
    });
  });
}

BackupManifest _manifest({Iterable<BackupManifestItem>? items}) {
  return BackupManifest(
    batchId: 'batch-2026-07-12',
    profileId: 'home-pc',
    sourceDevice: 'pixel-9',
    createdAtUtc: DateTime.utc(2026, 7, 12, 3, 4, 5),
    items: items ?? [_item(key: 'external:1')],
  );
}

BackupManifestItem _item({
  required String key,
  String path = 'DCIM/Camera/',
  String name = 'IMG_0001.jpg',
  int size = 100,
  String? sha256,
}) {
  return BackupManifestItem(
    snapshotItem: MediaSnapshotItem(
      mediaKey: key,
      relativePath: path,
      displayName: name,
      sizeBytes: size,
      modifiedAtSeconds: 1700000000,
      generationModified: 7,
      mimeType: 'image/jpeg',
    ),
    sha256: sha256,
  );
}

Map<String, Object?> _document() {
  return jsonDecode(codecForFixture.encode(_manifest()))
      as Map<String, Object?>;
}

const codecForFixture = BackupManifestCodec();
