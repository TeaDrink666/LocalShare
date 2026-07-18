import 'dart:convert';

import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';

/// Strict JSON codec for the versioned backup manifest schema.
///
/// Encoding recursively orders object keys and [BackupManifest] orders its
/// item list, producing the same compact UTF-8 JSON text for equivalent input.
final class BackupManifestCodec {
  const BackupManifestCodec();

  String encode(BackupManifest manifest) {
    final document = <String, Object?>{
      'schemaVersion': manifest.schemaVersion,
      'batchId': manifest.batchId,
      'profileId': manifest.profileId,
      'sourceDevice': manifest.sourceDevice,
      'createdAtUtc': manifest.createdAtUtc.toIso8601String(),
      'itemCount': manifest.itemCount,
      'totalBytes': manifest.totalBytes,
      'items': manifest.items.map(_encodeItem).toList(growable: false),
    };

    return jsonEncode(_sortObjectKeys(document));
  }

  BackupManifest decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid backup manifest JSON: ${error.message}');
    }

    final document = _requireObject(decoded, r'$');
    _requireExactKeys(
      document,
      const {
        'schemaVersion',
        'batchId',
        'profileId',
        'sourceDevice',
        'createdAtUtc',
        'itemCount',
        'totalBytes',
        'items',
      },
      r'$',
    );

    final schemaVersion = _requireInt(
      document['schemaVersion'],
      r'$.schemaVersion',
    );
    if (schemaVersion != backupManifestSchemaVersion) {
      throw FormatException(
        'Unsupported backup manifest schema version: $schemaVersion',
      );
    }

    final declaredItemCount = _requireNonNegativeInt(
      document['itemCount'],
      r'$.itemCount',
    );
    final declaredTotalBytes = _requireNonNegativeInt(
      document['totalBytes'],
      r'$.totalBytes',
    );
    final encodedItems = _requireList(document['items'], r'$.items');
    final items = <BackupManifestItem>[];
    for (var index = 0; index < encodedItems.length; index++) {
      items.add(_decodeItem(encodedItems[index], index));
    }

    if (declaredItemCount != items.length) {
      throw FormatException(
        r'$.itemCount does not match $.items: '
        '$declaredItemCount != ${items.length}',
      );
    }
    final calculatedTotalBytes = items.fold<int>(
      0,
      (total, item) => total + item.snapshotItem.sizeBytes,
    );
    if (declaredTotalBytes != calculatedTotalBytes) {
      throw FormatException(
        r'$.totalBytes does not match $.items: '
        '$declaredTotalBytes != $calculatedTotalBytes',
      );
    }

    final createdAtUtc = _requireUtcTimestamp(
      document['createdAtUtc'],
      r'$.createdAtUtc',
    );

    try {
      return BackupManifest(
        schemaVersion: schemaVersion,
        batchId: _requireString(document['batchId'], r'$.batchId'),
        profileId: _requireString(document['profileId'], r'$.profileId'),
        sourceDevice: _requireString(
          document['sourceDevice'],
          r'$.sourceDevice',
        ),
        createdAtUtc: createdAtUtc,
        items: items,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid backup manifest: ${error.message}');
    }
  }

  Map<String, Object?> _encodeItem(BackupManifestItem item) {
    final media = item.snapshotItem;
    return <String, Object?>{
      'mediaKey': media.mediaKey,
      'relativePath': media.relativePath,
      'displayName': media.displayName,
      'sizeBytes': media.sizeBytes,
      'modifiedAtSeconds': media.modifiedAtSeconds,
      'generationModified': media.generationModified,
      'mimeType': media.mimeType,
      'sha256': item.sha256,
    };
  }

  BackupManifestItem _decodeItem(Object? value, int index) {
    final path = '\$.items[$index]';
    final item = _requireObject(value, path);
    _requireExactKeys(
      item,
      const {
        'mediaKey',
        'relativePath',
        'displayName',
        'sizeBytes',
        'modifiedAtSeconds',
        'generationModified',
        'mimeType',
        'sha256',
      },
      path,
    );

    final generationValue = item['generationModified'];
    final generationModified = generationValue == null
        ? null
        : _requireNonNegativeInt(
            generationValue,
            '$path.generationModified',
          );
    final shaValue = item['sha256'];
    final sha256 =
        shaValue == null ? null : _requireString(shaValue, '$path.sha256');
    final mediaKey = _requireString(item['mediaKey'], '$path.mediaKey');
    if (mediaKey.isEmpty) {
      throw FormatException('$path.mediaKey must not be empty');
    }
    final displayName = _requireString(
      item['displayName'],
      '$path.displayName',
    );
    if (displayName.isEmpty) {
      throw FormatException('$path.displayName must not be empty');
    }

    try {
      return BackupManifestItem(
        snapshotItem: MediaSnapshotItem(
          mediaKey: mediaKey,
          relativePath: _requireString(
            item['relativePath'],
            '$path.relativePath',
          ),
          displayName: displayName,
          sizeBytes: _requireNonNegativeInt(
            item['sizeBytes'],
            '$path.sizeBytes',
          ),
          modifiedAtSeconds: _requireNonNegativeInt(
            item['modifiedAtSeconds'],
            '$path.modifiedAtSeconds',
          ),
          generationModified: generationModified,
          mimeType: _requireString(item['mimeType'], '$path.mimeType'),
        ),
        sha256: sha256,
      );
    } on ArgumentError catch (error) {
      throw FormatException('$path is invalid: ${error.message}');
    }
  }
}

Map<String, Object?> _requireObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be a JSON object');
  }
  return value;
}

List<Object?> _requireList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw FormatException('$path must be a JSON array');
  }
  return value;
}

String _requireString(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return value;
}

int _requireInt(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer');
  }
  return value;
}

int _requireNonNegativeInt(Object? value, String path) {
  final integer = _requireInt(value, path);
  if (integer < 0) {
    throw FormatException('$path must not be negative');
  }
  return integer;
}

DateTime _requireUtcTimestamp(Object? value, String path) {
  final text = _requireString(value, path);
  if (!text.endsWith('Z')) {
    throw FormatException('$path must use the UTC `Z` designator');
  }

  final DateTime parsed;
  try {
    parsed = DateTime.parse(text);
  } on FormatException {
    throw FormatException('$path must be a valid ISO-8601 timestamp');
  }
  if (!parsed.isUtc) {
    throw FormatException('$path must be UTC');
  }
  return parsed;
}

void _requireExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
) {
  final missing = expected.difference(value.keys.toSet()).toList()..sort();
  final unexpected = value.keys.toSet().difference(expected).toList()..sort();
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    throw FormatException(
      '$path has an invalid field set'
      '${missing.isEmpty ? '' : '; missing: ${missing.join(', ')}'}'
      '${unexpected.isEmpty ? '' : '; unexpected: ${unexpected.join(', ')}'}',
    );
  }
}

Object? _sortObjectKeys(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortObjectKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sortObjectKeys).toList(growable: false);
  }
  return value;
}
