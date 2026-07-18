import 'package:localsend_app/features/backup/domain/media_snapshot.dart';

/// The last version of a media item confirmed as persisted by one target.
///
/// Only a native receiver acknowledgement or explicit browser confirmation
/// should create an entry. Merely starting or completing an HTTP response is
/// not confirmation that the destination persisted the file.
final class BackupLedgerEntry {
  const BackupLedgerEntry({
    required this.mediaKey,
    required this.relativePath,
    required this.displayName,
    required this.sizeBytes,
    required this.modifiedAtSeconds,
    required this.generationModified,
    required this.mimeType,
  })  : assert(mediaKey != ''),
        assert(displayName != ''),
        assert(sizeBytes >= 0),
        assert(modifiedAtSeconds >= 0),
        assert(generationModified == null || generationModified >= 0);

  factory BackupLedgerEntry.fromConfirmedItem(MediaSnapshotItem item) {
    return BackupLedgerEntry(
      mediaKey: item.mediaKey,
      relativePath: item.relativePath,
      displayName: item.displayName,
      sizeBytes: item.sizeBytes,
      modifiedAtSeconds: item.modifiedAtSeconds,
      generationModified: item.generationModified,
      mimeType: item.mimeType,
    );
  }

  final String mediaKey;
  final String relativePath;
  final String displayName;
  final int sizeBytes;
  final int modifiedAtSeconds;
  final int? generationModified;
  final String mimeType;

  /// Whether [item] is exactly the version represented by this confirmation.
  ///
  /// Path and descriptive metadata participate in the comparison so a rename,
  /// move, or MIME correction produces a new backup item rather than leaving
  /// the target ledger stale.
  bool matches(MediaSnapshotItem item) {
    return mediaKey == item.mediaKey &&
        relativePath == item.relativePath &&
        displayName == item.displayName &&
        sizeBytes == item.sizeBytes &&
        modifiedAtSeconds == item.modifiedAtSeconds &&
        generationModified == item.generationModified &&
        mimeType == item.mimeType;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BackupLedgerEntry &&
            mediaKey == other.mediaKey &&
            relativePath == other.relativePath &&
            displayName == other.displayName &&
            sizeBytes == other.sizeBytes &&
            modifiedAtSeconds == other.modifiedAtSeconds &&
            generationModified == other.generationModified &&
            mimeType == other.mimeType;
  }

  @override
  int get hashCode => Object.hash(
        mediaKey,
        relativePath,
        displayName,
        sizeBytes,
        modifiedAtSeconds,
        generationModified,
        mimeType,
      );

  @override
  String toString() {
    return 'BackupLedgerEntry('
        'mediaKey: $mediaKey, '
        'relativePath: $relativePath, '
        'displayName: $displayName, '
        'sizeBytes: $sizeBytes, '
        'modifiedAtSeconds: $modifiedAtSeconds, '
        'generationModified: $generationModified, '
        'mimeType: $mimeType)';
  }
}
