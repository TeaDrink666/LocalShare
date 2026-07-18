import 'package:localsend_app/features/backup/domain/media_snapshot.dart';

/// The only backup-manifest schema understood by this build.
const int backupManifestSchemaVersion = 1;

/// Stable metadata for one media item in a persisted backup manifest.
///
/// The live byte representation (for example an Android `content://` URI) is
/// deliberately absent. Callers must resolve [snapshotItem.mediaKey] against
/// the current media catalogue immediately before opening the source.
final class BackupManifestItem {
  BackupManifestItem({
    required this.snapshotItem,
    this.sha256,
  }) {
    _validateSnapshotItem(snapshotItem);
    _validateSha256(sha256);
  }

  final MediaSnapshotItem snapshotItem;

  /// A lowercase hexadecimal SHA-256 digest when one has been calculated.
  ///
  /// Hashing media is intentionally lazy, so the field is persisted as
  /// `null` until a later verification step supplies a strong digest.
  final String? sha256;
}

/// An immutable, deterministic batch of media selected for one target.
///
/// [profileId] identifies the destination computer/profile. Ledgers and
/// persisted manifest files must be partitioned by this value so confirming a
/// backup for one computer never advances another computer's state.
final class BackupManifest {
  BackupManifest({
    this.schemaVersion = backupManifestSchemaVersion,
    required this.batchId,
    required this.profileId,
    required this.sourceDevice,
    required this.createdAtUtc,
    required Iterable<BackupManifestItem> items,
  }) : items = _freezeAndValidateItems(items) {
    _validateSchemaVersion(schemaVersion);
    _validateIdentifier(batchId, fieldName: 'batchId');
    _validateIdentifier(profileId, fieldName: 'profileId');
    _validateIdentifier(sourceDevice, fieldName: 'sourceDevice');
    _validateUtc(createdAtUtc);
  }

  /// Creates a manifest whose hashes have not been calculated yet.
  factory BackupManifest.fromMediaItems({
    required String batchId,
    required String profileId,
    required String sourceDevice,
    required DateTime createdAtUtc,
    required Iterable<MediaSnapshotItem> items,
  }) {
    return BackupManifest(
      batchId: batchId,
      profileId: profileId,
      sourceDevice: sourceDevice,
      createdAtUtc: createdAtUtc,
      items: items.map(
        (item) => BackupManifestItem(snapshotItem: item),
      ),
    );
  }

  final int schemaVersion;
  final String batchId;

  /// Stable ID of the destination computer/profile, not its display name.
  final String profileId;

  /// Stable ID of the phone or other source device.
  final String sourceDevice;

  /// Manifest creation time. Local-time [DateTime] values are rejected.
  final DateTime createdAtUtc;

  /// Items sorted by relative path, display name, and media key.
  final List<BackupManifestItem> items;

  int get itemCount => items.length;

  int get totalBytes => items.fold<int>(
        0,
        (total, item) => total + item.snapshotItem.sizeBytes,
      );
}

List<BackupManifestItem> _freezeAndValidateItems(
  Iterable<BackupManifestItem> source,
) {
  final items = List<BackupManifestItem>.of(source)
    ..sort(_compareManifestItems);
  final mediaKeys = <String>{};
  final destinationPaths = <String>{};

  for (final item in items) {
    _validateSnapshotItem(item.snapshotItem);
    _validateSha256(item.sha256);

    final media = item.snapshotItem;
    if (!mediaKeys.add(media.mediaKey)) {
      throw ArgumentError.value(
        media.mediaKey,
        'items',
        'Duplicate mediaKey',
      );
    }

    final destinationPath = '${media.relativePath}${media.displayName}';
    if (!destinationPaths.add(destinationPath)) {
      throw ArgumentError.value(
        destinationPath,
        'items',
        'Duplicate destination path',
      );
    }
  }

  return List<BackupManifestItem>.unmodifiable(items);
}

int _compareManifestItems(BackupManifestItem left, BackupManifestItem right) {
  final leftMedia = left.snapshotItem;
  final rightMedia = right.snapshotItem;

  final pathComparison = leftMedia.relativePath.compareTo(
    rightMedia.relativePath,
  );
  if (pathComparison != 0) {
    return pathComparison;
  }

  final nameComparison = leftMedia.displayName.compareTo(
    rightMedia.displayName,
  );
  if (nameComparison != 0) {
    return nameComparison;
  }

  return leftMedia.mediaKey.compareTo(rightMedia.mediaKey);
}

void _validateSchemaVersion(int value) {
  if (value != backupManifestSchemaVersion) {
    throw ArgumentError.value(
      value,
      'schemaVersion',
      'Unsupported backup manifest schema version',
    );
  }
}

void _validateIdentifier(String value, {required String fieldName}) {
  if (value.trim().isEmpty || _containsControlCharacter(value)) {
    throw ArgumentError.value(
      value,
      fieldName,
      'Must be non-empty and contain no control characters',
    );
  }
}

void _validateUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(
      value,
      'createdAtUtc',
      'Must be a UTC DateTime',
    );
  }
}

void _validateSnapshotItem(MediaSnapshotItem item) {
  _validateIdentifier(item.mediaKey, fieldName: 'mediaKey');
  _validateRelativePath(item.relativePath);
  _validateDisplayName(item.displayName);

  if (item.sizeBytes < 0) {
    throw ArgumentError.value(
      item.sizeBytes,
      'sizeBytes',
      'Must not be negative',
    );
  }
  if (item.modifiedAtSeconds < 0) {
    throw ArgumentError.value(
      item.modifiedAtSeconds,
      'modifiedAtSeconds',
      'Must not be negative',
    );
  }
  final generationModified = item.generationModified;
  if (generationModified != null && generationModified < 0) {
    throw ArgumentError.value(
      generationModified,
      'generationModified',
      'Must not be negative',
    );
  }
  if (_containsControlCharacter(item.mimeType)) {
    throw ArgumentError.value(
      item.mimeType,
      'mimeType',
      'Must contain no control characters',
    );
  }
}

void _validateRelativePath(String value) {
  if (_containsControlCharacter(value) || value.contains(r'\')) {
    throw ArgumentError.value(
      value,
      'relativePath',
      r'Must use `/` separators and contain no control characters',
    );
  }
  if (value.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'Must be relative',
    );
  }
  if (value.isNotEmpty && !value.endsWith('/')) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'Must be empty or end with `/`',
    );
  }

  final segments = value.isEmpty
      ? const <String>[]
      : value.substring(0, value.length - 1).split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'Must be normalized and contain no empty, `.` or `..` segments',
    );
  }
}

void _validateDisplayName(String value) {
  if (value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains(r'\') ||
      _containsControlCharacter(value)) {
    throw ArgumentError.value(
      value,
      'displayName',
      'Must be a single non-empty path component',
    );
  }
}

void _validateSha256(String? value) {
  if (value != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'sha256',
      'Must be null or 64 lowercase hexadecimal characters',
    );
  }
}

bool _containsControlCharacter(String value) {
  return value.codeUnits.any((codeUnit) => codeUnit < 0x20);
}
