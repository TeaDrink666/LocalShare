import 'package:common/model/file_type.dart';
import 'package:localsend_app/features/backup/data/android_media_catalog.dart';
import 'package:localsend_app/features/backup/domain/backup_domain.dart';
import 'package:localsend_app/features/backup/manifest/manifest.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart'
    as android_channel;
import 'package:test/test.dart';

void main() {
  group('AndroidMediaCatalog.scan', () {
    test('aggregates pages and reports cumulative progress', () async {
      final calls = <String>[];
      final progress = <int>[];
      final catalog = AndroidMediaCatalog(
        pageLoader: ({
          int afterId = 0,
          int limit = 250,
          bool includeImages = true,
          bool includeVideos = true,
        }) async {
          calls.add('$afterId:$limit:$includeImages:$includeVideos');
          if (afterId == 0) {
            return android_channel.BackupMediaPage(
              items: [
                _media(id: 1, name: 'IMG_0001.jpg'),
                _media(id: 2, name: 'IMG_0002.jpg'),
              ],
              nextAfterId: 2,
              hasMore: true,
            );
          }
          return android_channel.BackupMediaPage(
            items: [_media(id: 3, name: 'VID_0003.mp4')],
            nextAfterId: 3,
            hasMore: false,
          );
        },
      );

      final scan = await catalog.scan(
        includeImages: true,
        includeVideos: false,
        pageSize: 2,
        onProgress: progress.add,
      );

      expect(calls, ['0:2:true:false', '2:2:true:false']);
      expect(progress, [2, 3]);
      expect(
        scan.items.map((item) => item.mediaKey),
        ['external:1', 'external:2', 'external:3'],
      );
      expect(
        scan.snapshot.items.map((item) => item.displayName),
        ['IMG_0001.jpg', 'IMG_0002.jpg', 'VID_0003.mp4'],
      );
    });

    test('does not call the platform when no media types are selected',
        () async {
      var loaderCalls = 0;
      final progress = <int>[];
      final catalog = AndroidMediaCatalog(
        pageLoader: ({
          int afterId = 0,
          int limit = 250,
          bool includeImages = true,
          bool includeVideos = true,
        }) async {
          loaderCalls++;
          throw StateError('The page loader must not be called.');
        },
      );

      final scan = await catalog.scan(
        includeImages: false,
        includeVideos: false,
        onProgress: progress.add,
      );

      expect(loaderCalls, 0);
      expect(progress, isEmpty);
      expect(scan.items, isEmpty);
      expect(scan.snapshot.items, isEmpty);
    });

    test('rejects pagination that cannot advance', () async {
      final invalidPages = [
        android_channel.BackupMediaPage(
          items: [_media(id: 1)],
          nextAfterId: 0,
          hasMore: true,
        ),
        const android_channel.BackupMediaPage(
          items: [],
          nextAfterId: 1,
          hasMore: true,
        ),
      ];

      for (final page in invalidPages) {
        final catalog = AndroidMediaCatalog(
          pageLoader: ({
            int afterId = 0,
            int limit = 250,
            bool includeImages = true,
            bool includeVideos = true,
          }) async =>
              page,
        );

        await expectLater(
          catalog.scan(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('did not advance'),
            ),
          ),
        );
      }
    });

    test('rejects duplicate media keys across pages', () async {
      final catalog = AndroidMediaCatalog(
        pageLoader: ({
          int afterId = 0,
          int limit = 250,
          bool includeImages = true,
          bool includeVideos = true,
        }) async {
          if (afterId == 0) {
            return android_channel.BackupMediaPage(
              items: [_media(id: 7, name: 'first.jpg')],
              nextAfterId: 7,
              hasMore: true,
            );
          }
          return android_channel.BackupMediaPage(
            items: [_media(id: 7, name: 'duplicate.jpg')],
            nextAfterId: 7,
            hasMore: false,
          );
        },
      );

      await expectLater(
        catalog.scan(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicate media keys'),
          ),
        ),
      );
    });
  });

  group('AndroidMediaCatalogScan', () {
    test('normalizes MediaStore relative paths and rejects traversal', () {
      final scan = AndroidMediaCatalogScan([
        _media(
          id: 1,
          relativePath: r'\DCIM\\.\Camera///',
        ),
      ]);

      expect(scan.snapshot.items.single.relativePath, 'DCIM/Camera/');

      final plan = _plan(scan);
      expect(scan.crossFilesForPlan(plan).single.name, 'DCIM/Camera/item.jpg');

      final unsafeScan = AndroidMediaCatalogScan([
        _media(id: 2, relativePath: 'DCIM/../Pictures/'),
      ]);
      expect(() => unsafeScan.snapshot, throwsA(isA<FormatException>()));
    });

    test('maps image and video sources to transferable CrossFiles', () {
      final scan = AndroidMediaCatalogScan([
        _media(
          id: 1,
          relativePath: 'Pictures/',
          name: 'photo.payload',
          size: 123,
          modified: 1700000001,
          mimeType: 'image/heic',
          contentUri: 'content://media/external/images/media/1',
        ),
        _media(
          id: 2,
          relativePath: 'Movies/',
          name: 'clip.payload',
          size: 456,
          modified: 1700000002,
          mimeType: 'video/x-matroska',
          contentUri: 'content://media/external/video/media/2',
        ),
      ]);

      final files = scan.crossFilesForPlan(_plan(scan));
      final filesByName = {for (final file in files) file.name: file};
      final image = filesByName['Pictures/photo.payload']!;
      final video = filesByName['Movies/clip.payload']!;

      expect(image.fileType, FileType.image);
      expect(image.path, 'content://media/external/images/media/1');
      expect(image.size, 123);
      expect(
          image.lastModified,
          DateTime.fromMillisecondsSinceEpoch(
            1700000001000,
            isUtc: true,
          ));
      expect(image.lastModified!.isUtc, isTrue);
      expect(video.fileType, FileType.video);
      expect(video.path, 'content://media/external/video/media/2');
      expect(video.size, 456);
      expect(
          video.lastModified,
          DateTime.fromMillisecondsSinceEpoch(
            1700000002000,
            isUtc: true,
          ));
    });

    test('keeps primary paths and prefixes secondary-volume destinations', () {
      final scan = AndroidMediaCatalogScan([
        _media(id: 1, volume: 'external_primary'),
        _media(id: 1, volume: '0123-4567'),
      ]);
      final snapshot = scan.snapshot;
      final pathsByKey = {
        for (final item in snapshot.items) item.mediaKey: item.relativePath,
      };

      expect(pathsByKey['external_primary:1'], 'DCIM/Camera/');
      expect(
        pathsByKey['0123-4567:1'],
        'Storage/0123-4567/DCIM/Camera/',
      );
      expect(pathsByKey.values.toSet(), hasLength(2));

      final manifest = BackupManifest.fromMediaItems(
        batchId: 'batch',
        profileId: 'desktop',
        sourceDevice: 'phone',
        createdAtUtc: DateTime.utc(2026, 7, 12),
        items: snapshot.items,
      );
      expect(manifest.itemCount, 2);

      final crossFileNames =
          scan.crossFilesForPlan(_plan(scan)).map((file) => file.name).toSet();
      expect(crossFileNames, {
        'DCIM/Camera/item.jpg',
        'Storage/0123-4567/DCIM/Camera/item.jpg',
      });
    });

    test('sanitizes invalid secondary-volume characters deterministically', () {
      const unsafeVolume = 'SD:/card*?<bad>|';
      const sameSanitizedBase = 'SD?/card*?<bad>|';
      final first = AndroidMediaCatalogScan([
        _media(id: 1, volume: unsafeVolume),
      ]).snapshot.items.single.relativePath;
      final second = AndroidMediaCatalogScan([
        _media(id: 2, volume: unsafeVolume),
      ]).snapshot.items.single.relativePath;
      final collisionCandidate = AndroidMediaCatalogScan([
        _media(id: 3, volume: sameSanitizedBase),
      ]).snapshot.items.single.relativePath;
      final volumeSegment = first.split('/')[1];

      expect(first, second);
      expect(collisionCandidate, isNot(first));
      expect(first, startsWith('Storage/'));
      expect(first, endsWith('/DCIM/Camera/'));
      expect(volumeSegment, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(volumeSegment, startsWith('SD__card___bad__'));

      expect(
        () => BackupManifest.fromMediaItems(
          batchId: 'batch',
          profileId: 'desktop',
          sourceDevice: 'phone',
          createdAtUtc: DateTime.utc(2026, 7, 12),
          items: AndroidMediaCatalogScan([
            _media(id: 1, volume: unsafeVolume),
          ]).snapshot.items,
        ),
        returnsNormally,
      );
    });

    test('rejects a stale plan when the current source changed or vanished',
        () {
      final original = AndroidMediaCatalogScan([
        _media(id: 1, size: 100, volume: '0123-4567'),
      ]);
      final stalePlan = _plan(original);
      final changed = AndroidMediaCatalogScan([
        _media(id: 1, size: 101, volume: '0123-4567'),
      ]);
      final missing = AndroidMediaCatalogScan([
        _media(id: 2, size: 100, volume: '0123-4567'),
      ]);

      for (final currentScan in [changed, missing]) {
        expect(
          () => currentScan.crossFilesForPlan(stalePlan),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('0123-4567:1'),
            ),
          ),
        );
      }
    });

    test('rejects duplicate media keys before resolving a plan', () {
      expect(
        () => AndroidMediaCatalogScan([
          _media(id: 4, name: 'first.jpg'),
          _media(id: 4, name: 'second.jpg'),
        ]),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

BackupPlan _plan(AndroidMediaCatalogScan scan) {
  return const IncrementalBackupPlanner().createPlan(
    currentSnapshot: scan.snapshot,
    confirmedLedger: const [],
  );
}

android_channel.BackupMediaItem _media({
  required int id,
  String volume = 'external',
  String relativePath = 'DCIM/Camera/',
  String name = 'item.jpg',
  int size = 100,
  int modified = 1700000000,
  int? generation = 1,
  String mimeType = 'image/jpeg',
  String? contentUri,
}) {
  return android_channel.BackupMediaItem(
    mediaKey: '$volume:$id',
    contentUri: contentUri ?? 'content://media/$volume/file/$id',
    relativePath: relativePath,
    displayName: name,
    sizeBytes: size,
    modifiedAtSeconds: modified,
    generationModified: generation,
    mimeType: mimeType,
  );
}
