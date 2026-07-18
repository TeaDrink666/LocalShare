import 'package:localsend_app/features/backup/domain/backup_domain.dart';
import 'package:test/test.dart';

void main() {
  const planner = IncrementalBackupPlanner();

  group('IncrementalBackupPlanner', () {
    test('plans every item as new when the confirmed ledger is empty', () {
      final first = _media(
        key: 'external:1',
        name: 'IMG_0001.jpg',
        size: 120,
      );
      final second = _media(
        key: 'external:2',
        name: 'VID_0002.mp4',
        size: 880,
        mimeType: 'video/mp4',
      );

      final plan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot([second, first]),
        confirmedLedger: const [],
      );

      expect(
        plan.items.map((item) => item.snapshotItem),
        [first, second],
      );
      expect(
        plan.items.map((item) => item.reason),
        everyElement(BackupPlanReason.newItem),
      );
      expect(
        plan.items.map((item) => item.previousEntry),
        everyElement(isNull),
      );
      expect(plan.plannedItemCount, 2);
      expect(plan.currentItemCount, 2);
      expect(plan.newItemCount, 2);
      expect(plan.changedItemCount, 0);
      expect(plan.unchangedItemCount, 0);
      expect(plan.ledgerOnlyItemCount, 0);
      expect(plan.totalBytes, 1000);
      expect(plan.isEmpty, isFalse);
    });

    test('skips an item identical to its confirmed ledger entry', () {
      final media = _media(key: 'external:1');

      final plan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot([media]),
        confirmedLedger: [BackupLedgerEntry.fromConfirmedItem(media)],
      );

      expect(plan.items, isEmpty);
      expect(plan.plannedItemCount, 0);
      expect(plan.currentItemCount, 1);
      expect(plan.newItemCount, 0);
      expect(plan.changedItemCount, 0);
      expect(plan.unchangedItemCount, 1);
      expect(plan.ledgerOnlyItemCount, 0);
      expect(plan.totalBytes, 0);
      expect(plan.isEmpty, isTrue);
    });

    test('plans a changed item with its prior confirmed entry', () {
      final before = _media(
        key: 'external:1',
        size: 100,
        modified: 1700000000,
        generation: 9,
      );
      final after = _media(
        key: 'external:1',
        size: 250,
        modified: 1700000010,
        generation: 10,
      );
      final previousEntry = BackupLedgerEntry.fromConfirmedItem(before);

      final plan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot([after]),
        confirmedLedger: [previousEntry],
      );

      expect(plan.items, hasLength(1));
      expect(plan.items.single.snapshotItem, after);
      expect(plan.items.single.reason, BackupPlanReason.changedItem);
      expect(plan.items.single.previousEntry, previousEntry);
      expect(plan.newItemCount, 0);
      expect(plan.changedItemCount, 1);
      expect(plan.unchangedItemCount, 0);
      expect(plan.totalBytes, 250);
    });

    test('treats each persisted signature field as a change', () {
      final original = _media(key: 'external:1');
      final ledger = [BackupLedgerEntry.fromConfirmedItem(original)];
      final changedItems = <MediaSnapshotItem>[
        _media(key: original.mediaKey, size: original.sizeBytes + 1),
        _media(
          key: original.mediaKey,
          modified: original.modifiedAtSeconds + 1,
        ),
        _media(
          key: original.mediaKey,
          generation: original.generationModified! + 1,
        ),
        _media(key: original.mediaKey, path: 'Pictures/Edited/'),
        _media(key: original.mediaKey, name: 'renamed.jpg'),
        _media(key: original.mediaKey, mimeType: 'image/png'),
      ];

      for (final changed in changedItems) {
        final plan = planner.createPlan(
          currentSnapshot: MediaStoreSnapshot([changed]),
          confirmedLedger: ledger,
        );

        expect(
          plan.items.single.reason,
          BackupPlanReason.changedItem,
          reason: 'Expected $changed to differ from $original',
        );
      }
    });

    test('does not propagate ledger entries absent from the snapshot', () {
      final present = _media(key: 'external:present');
      final absent = _media(key: 'external:removed', name: 'removed.jpg');

      final plan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot([present]),
        confirmedLedger: [
          BackupLedgerEntry.fromConfirmedItem(present),
          BackupLedgerEntry.fromConfirmedItem(absent),
        ],
      );

      expect(plan.items, isEmpty);
      expect(plan.currentItemCount, 1);
      expect(plan.unchangedItemCount, 1);
      expect(plan.ledgerOnlyItemCount, 1);
      expect(plan.totalBytes, 0);
    });

    test('rejects duplicate keys in the current snapshot', () {
      final snapshot = MediaStoreSnapshot([
        _media(key: 'external:duplicate', name: 'first.jpg'),
        _media(key: 'external:duplicate', name: 'second.jpg'),
      ]);

      expect(
        () => planner.createPlan(
          currentSnapshot: snapshot,
          confirmedLedger: const [],
        ),
        throwsA(
          isA<DuplicateMediaKeyException>()
              .having(
                (error) => error.mediaKey,
                'mediaKey',
                'external:duplicate',
              )
              .having(
                (error) => error.source,
                'source',
                DuplicateMediaKeySource.currentSnapshot,
              ),
        ),
      );
    });

    test('rejects duplicate keys in the confirmed ledger', () {
      final media = _media(key: 'external:duplicate');
      final entry = BackupLedgerEntry.fromConfirmedItem(media);

      expect(
        () => planner.createPlan(
          currentSnapshot: MediaStoreSnapshot([media]),
          confirmedLedger: [entry, entry],
        ),
        throwsA(
          isA<DuplicateMediaKeyException>()
              .having(
                (error) => error.mediaKey,
                'mediaKey',
                'external:duplicate',
              )
              .having(
                (error) => error.source,
                'source',
                DuplicateMediaKeySource.confirmedLedger,
              ),
        ),
      );
    });

    test('uses path, name, then key for deterministic ordering', () {
      final items = [
        _media(key: 'key-3', path: 'Pictures/', name: 'same.jpg'),
        _media(key: 'key-2', path: 'DCIM/', name: 'z.jpg'),
        _media(key: 'key-1', path: 'DCIM/', name: 'a.jpg'),
        _media(key: 'key-0', path: 'Pictures/', name: 'same.jpg'),
      ];

      final firstPlan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot(items),
        confirmedLedger: const [],
      );
      final secondPlan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot(items.reversed),
        confirmedLedger: const [],
      );

      final expectedKeys = ['key-1', 'key-2', 'key-0', 'key-3'];
      expect(
        firstPlan.items.map((item) => item.snapshotItem.mediaKey),
        expectedKeys,
      );
      expect(
        secondPlan.items.map((item) => item.snapshotItem.mediaKey),
        expectedKeys,
      );
    });

    test('includes a new zero-byte item without inflating total bytes', () {
      final emptyMedia = _media(key: 'external:empty', size: 0);

      final plan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot([emptyMedia]),
        confirmedLedger: const [],
      );

      expect(plan.items.single.snapshotItem, emptyMedia);
      expect(plan.items.single.reason, BackupPlanReason.newItem);
      expect(plan.newItemCount, 1);
      expect(plan.totalBytes, 0);
    });

    test('preserves and deterministically orders Unicode paths and names', () {
      final chinese = _media(
        key: '外部存储:照片',
        path: '相机/旅行/',
        name: '夏天🌻.jpg',
      );
      final japanese = _media(
        key: '外部ストレージ:写真',
        path: 'カメラ/旅行/',
        name: '夏休み🎐.jpg',
      );

      final plan = planner.createPlan(
        currentSnapshot: MediaStoreSnapshot([chinese, japanese]),
        confirmedLedger: const [],
      );

      expect(
        plan.items.map((item) => item.snapshotItem),
        [japanese, chinese],
      );
      expect(plan.items.last.snapshotItem.displayName, '夏天🌻.jpg');
    });

    test('uses the snapshot frozen at scan completion', () {
      final source = <MediaSnapshotItem>[_media(key: 'external:1')];
      final snapshot = MediaStoreSnapshot(source);
      source
        ..clear()
        ..add(_media(key: 'external:2'));

      final plan = planner.createPlan(
        currentSnapshot: snapshot,
        confirmedLedger: const [],
      );

      expect(
        plan.items.single.snapshotItem.mediaKey,
        'external:1',
      );
      expect(
        () => snapshot.items.add(_media(key: 'external:3')),
        throwsUnsupportedError,
      );
      expect(
        () => plan.items.clear(),
        throwsUnsupportedError,
      );
    });
  });
}

MediaSnapshotItem _media({
  required String key,
  String path = 'DCIM/Camera/',
  String name = 'IMG_0001.jpg',
  int size = 100,
  int modified = 1700000000,
  int? generation = 1,
  String mimeType = 'image/jpeg',
}) {
  return MediaSnapshotItem(
    mediaKey: key,
    relativePath: path,
    displayName: name,
    sizeBytes: size,
    modifiedAtSeconds: modified,
    generationModified: generation,
    mimeType: mimeType,
  );
}
