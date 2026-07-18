/// An immutable item captured from Android's MediaStore for one backup scan.
///
/// [mediaKey] is a stable, platform-provided identity. Android adapters should
/// use a value such as `volumeName:mediaStoreId`; a display name is not a
/// stable identity.
final class MediaSnapshotItem {
  const MediaSnapshotItem({
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

  /// Stable platform identity, for example `external_primary:1234`.
  final String mediaKey;

  /// MediaStore-relative directory, for example `DCIM/Camera/`.
  ///
  /// An empty value represents the source root. This value never includes
  /// [displayName].
  final String relativePath;

  final String displayName;
  final int sizeBytes;

  /// MediaStore's modification timestamp, expressed in Unix seconds.
  final int modifiedAtSeconds;

  /// MediaStore's generation counter when supported by the Android version.
  final int? generationModified;

  final String mimeType;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MediaSnapshotItem &&
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
    return 'MediaSnapshotItem('
        'mediaKey: $mediaKey, '
        'relativePath: $relativePath, '
        'displayName: $displayName, '
        'sizeBytes: $sizeBytes, '
        'modifiedAtSeconds: $modifiedAtSeconds, '
        'generationModified: $generationModified, '
        'mimeType: $mimeType)';
  }
}

/// A completed, eagerly frozen MediaStore scan.
///
/// Freezing the iterable prevents later mutations of a scanner's working list
/// from changing a plan while it is being prepared or transferred.
final class MediaStoreSnapshot {
  MediaStoreSnapshot(Iterable<MediaSnapshotItem> items)
      : items = List<MediaSnapshotItem>.unmodifiable(items);

  final List<MediaSnapshotItem> items;
}
