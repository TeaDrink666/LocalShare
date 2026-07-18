import 'package:localsend_app/features/backup/domain/backup_ledger_entry.dart';
import 'package:localsend_app/features/backup/domain/backup_plan.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';

enum DuplicateMediaKeySource { currentSnapshot, confirmedLedger }

final class DuplicateMediaKeyException implements Exception {
  const DuplicateMediaKeyException({
    required this.mediaKey,
    required this.source,
  });

  final String mediaKey;
  final DuplicateMediaKeySource source;

  @override
  String toString() {
    return 'DuplicateMediaKeyException('
        'mediaKey: $mediaKey, source: ${source.name})';
  }
}

/// Computes an incremental backup without performing I/O or mutating a ledger.
final class IncrementalBackupPlanner {
  const IncrementalBackupPlanner();

  BackupPlan createPlan({
    required MediaStoreSnapshot currentSnapshot,
    required Iterable<BackupLedgerEntry> confirmedLedger,
  }) {
    // Materialize the ledger before comparing so lazy or mutable iterables
    // cannot change part-way through planning.
    final frozenLedger = List<BackupLedgerEntry>.unmodifiable(confirmedLedger);
    final currentByKey = <String, MediaSnapshotItem>{};
    final ledgerByKey = <String, BackupLedgerEntry>{};

    for (final item in currentSnapshot.items) {
      if (currentByKey.containsKey(item.mediaKey)) {
        throw DuplicateMediaKeyException(
          mediaKey: item.mediaKey,
          source: DuplicateMediaKeySource.currentSnapshot,
        );
      }
      currentByKey[item.mediaKey] = item;
    }

    for (final entry in frozenLedger) {
      if (ledgerByKey.containsKey(entry.mediaKey)) {
        throw DuplicateMediaKeyException(
          mediaKey: entry.mediaKey,
          source: DuplicateMediaKeySource.confirmedLedger,
        );
      }
      ledgerByKey[entry.mediaKey] = entry;
    }

    final plannedItems = <BackupPlanItem>[];
    var unchangedItemCount = 0;

    for (final item in currentByKey.values) {
      final confirmedEntry = ledgerByKey[item.mediaKey];
      if (confirmedEntry == null) {
        plannedItems.add(
          BackupPlanItem(
            snapshotItem: item,
            reason: BackupPlanReason.newItem,
            previousEntry: null,
          ),
        );
      } else if (confirmedEntry.matches(item)) {
        unchangedItemCount++;
      } else {
        plannedItems.add(
          BackupPlanItem(
            snapshotItem: item,
            reason: BackupPlanReason.changedItem,
            previousEntry: confirmedEntry,
          ),
        );
      }
    }

    plannedItems.sort(_comparePlanItems);

    var ledgerOnlyItemCount = 0;
    for (final mediaKey in ledgerByKey.keys) {
      if (!currentByKey.containsKey(mediaKey)) {
        ledgerOnlyItemCount++;
      }
    }

    return BackupPlan(
      items: plannedItems,
      currentItemCount: currentByKey.length,
      unchangedItemCount: unchangedItemCount,
      ledgerOnlyItemCount: ledgerOnlyItemCount,
    );
  }

  /// Stable ordering for manifests and repeatable tests, independent of scan
  /// page order or ledger iteration order.
  static int _comparePlanItems(BackupPlanItem left, BackupPlanItem right) {
    final leftItem = left.snapshotItem;
    final rightItem = right.snapshotItem;

    var comparison = leftItem.relativePath.compareTo(rightItem.relativePath);
    if (comparison != 0) {
      return comparison;
    }

    comparison = leftItem.displayName.compareTo(rightItem.displayName);
    if (comparison != 0) {
      return comparison;
    }

    return leftItem.mediaKey.compareTo(rightItem.mediaKey);
  }
}
