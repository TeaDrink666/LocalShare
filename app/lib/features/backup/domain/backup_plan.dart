import 'package:localsend_app/features/backup/domain/backup_ledger_entry.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';

enum BackupPlanReason {
  /// No confirmed ledger entry exists for this stable media key.
  newItem,

  /// A confirmed entry exists, but its version or metadata differs.
  changedItem,
}

final class BackupPlanItem {
  const BackupPlanItem({
    required this.snapshotItem,
    required this.reason,
    required this.previousEntry,
  }) : assert(
          (reason == BackupPlanReason.newItem && previousEntry == null) ||
              (reason == BackupPlanReason.changedItem && previousEntry != null),
        );

  final MediaSnapshotItem snapshotItem;
  final BackupPlanReason reason;

  /// Last confirmed version, or `null` when [reason] is
  /// [BackupPlanReason.newItem].
  final BackupLedgerEntry? previousEntry;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BackupPlanItem &&
            snapshotItem == other.snapshotItem &&
            reason == other.reason &&
            previousEntry == other.previousEntry;
  }

  @override
  int get hashCode => Object.hash(snapshotItem, reason, previousEntry);
}

/// A deterministic, immutable set of files to transfer for one backup scan.
final class BackupPlan {
  factory BackupPlan({
    required Iterable<BackupPlanItem> items,
    required int currentItemCount,
    required int unchangedItemCount,
    required int ledgerOnlyItemCount,
  }) {
    final frozenItems = List<BackupPlanItem>.unmodifiable(items);
    var totalBytes = 0;
    var newItemCount = 0;
    var changedItemCount = 0;

    for (final item in frozenItems) {
      totalBytes += item.snapshotItem.sizeBytes;
      switch (item.reason) {
        case BackupPlanReason.newItem:
          newItemCount++;
        case BackupPlanReason.changedItem:
          changedItemCount++;
      }
    }

    if (currentItemCount < 0 ||
        unchangedItemCount < 0 ||
        ledgerOnlyItemCount < 0) {
      throw ArgumentError('Backup plan counts must not be negative.');
    }
    if (currentItemCount != frozenItems.length + unchangedItemCount) {
      throw ArgumentError(
        'currentItemCount must equal plannedItemCount + unchangedItemCount.',
      );
    }

    return BackupPlan._(
      items: frozenItems,
      totalBytes: totalBytes,
      currentItemCount: currentItemCount,
      newItemCount: newItemCount,
      changedItemCount: changedItemCount,
      unchangedItemCount: unchangedItemCount,
      ledgerOnlyItemCount: ledgerOnlyItemCount,
    );
  }

  const BackupPlan._({
    required this.items,
    required this.totalBytes,
    required this.currentItemCount,
    required this.newItemCount,
    required this.changedItemCount,
    required this.unchangedItemCount,
    required this.ledgerOnlyItemCount,
  });

  final List<BackupPlanItem> items;

  /// Number of bytes that this plan will transfer.
  final int totalBytes;

  /// Number of unique items in the frozen current snapshot.
  final int currentItemCount;

  final int newItemCount;
  final int changedItemCount;
  final int unchangedItemCount;

  /// Confirmed ledger entries absent from the current snapshot.
  ///
  /// This is informational only. The planner intentionally emits no delete
  /// action for these entries.
  final int ledgerOnlyItemCount;

  int get plannedItemCount => items.length;

  bool get isEmpty => items.isEmpty;
}
