import 'dart:convert';

import 'package:common/model/file_type.dart';
import 'package:localsend_app/features/backup/domain/backup_plan.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart'
    as android_channel;

typedef BackupMediaPageLoader = Future<android_channel.BackupMediaPage>
    Function({
  int afterId,
  int limit,
  bool includeImages,
  bool includeVideos,
});

typedef BackupScanProgress = void Function(int scannedItemCount);

/// One complete MediaStore inventory together with its live byte sources.
final class AndroidMediaCatalogScan {
  AndroidMediaCatalogScan(Iterable<android_channel.BackupMediaItem> items)
      : items = List<android_channel.BackupMediaItem>.unmodifiable(items),
        _itemsByKey = Map<String, android_channel.BackupMediaItem>.unmodifiable(
          {
            for (final item in items) item.mediaKey: item,
          },
        ) {
    if (this.items.length != _itemsByKey.length) {
      throw const FormatException('MediaStore returned duplicate media keys.');
    }
  }

  final List<android_channel.BackupMediaItem> items;
  final Map<String, android_channel.BackupMediaItem> _itemsByKey;

  MediaStoreSnapshot get snapshot => MediaStoreSnapshot(
        items.map(
          (item) => MediaSnapshotItem(
            mediaKey: item.mediaKey,
            relativePath: _destinationRelativePath(item),
            displayName: item.displayName,
            sizeBytes: item.sizeBytes,
            modifiedAtSeconds: item.modifiedAtSeconds,
            generationModified: item.generationModified,
            mimeType: item.mimeType,
          ),
        ),
      );

  /// Resolves a frozen plan back to current `content://` sources.
  ///
  /// Metadata is checked again so a caller cannot accidentally combine a plan
  /// from an older scan with newly reused MediaStore IDs.
  List<CrossFile> crossFilesForPlan(BackupPlan plan) {
    return List<CrossFile>.unmodifiable(
      plan.items.map((planned) {
        final snapshot = planned.snapshotItem;
        final source = _itemsByKey[snapshot.mediaKey];
        if (source == null || !_matches(source, snapshot)) {
          throw StateError(
            'Backup source changed after scanning: ${snapshot.mediaKey}',
          );
        }
        final relativePath = _destinationRelativePath(source);
        return CrossFile(
          name: '$relativePath${source.displayName}',
          fileType: _fileType(source),
          size: source.sizeBytes,
          thumbnail: null,
          asset: null,
          path: source.contentUri,
          bytes: null,
          lastModified: DateTime.fromMillisecondsSinceEpoch(
            source.modifiedAtSeconds * 1000,
            isUtc: true,
          ),
          lastAccessed: null,
        );
      }),
    );
  }
}

/// Paginates the Android platform channel without retaining mutable pages.
final class AndroidMediaCatalog {
  const AndroidMediaCatalog({
    BackupMediaPageLoader pageLoader = android_channel.scanBackupMedia,
  }) : _pageLoader = pageLoader;

  final BackupMediaPageLoader _pageLoader;

  Future<AndroidMediaCatalogScan> scan({
    bool includeImages = true,
    bool includeVideos = true,
    int pageSize = 250,
    BackupScanProgress? onProgress,
  }) async {
    if (!includeImages && !includeVideos) {
      return AndroidMediaCatalogScan(const []);
    }
    RangeError.checkValueInInterval(pageSize, 1, 1000, 'pageSize');

    final allItems = <android_channel.BackupMediaItem>[];
    var afterId = 0;
    while (true) {
      final page = await _pageLoader(
        afterId: afterId,
        limit: pageSize,
        includeImages: includeImages,
        includeVideos: includeVideos,
      );
      allItems.addAll(page.items);
      onProgress?.call(allItems.length);
      if (!page.hasMore) {
        break;
      }
      if (page.nextAfterId <= afterId || page.items.isEmpty) {
        throw const FormatException(
          'MediaStore pagination did not advance.',
        );
      }
      afterId = page.nextAfterId;
    }

    return AndroidMediaCatalogScan(allItems);
  }
}

bool _matches(
  android_channel.BackupMediaItem source,
  MediaSnapshotItem snapshot,
) {
  return source.mediaKey == snapshot.mediaKey &&
      _destinationRelativePath(source) == snapshot.relativePath &&
      source.displayName == snapshot.displayName &&
      source.sizeBytes == snapshot.sizeBytes &&
      source.modifiedAtSeconds == snapshot.modifiedAtSeconds &&
      source.generationModified == snapshot.generationModified &&
      source.mimeType == snapshot.mimeType;
}

String _destinationRelativePath(android_channel.BackupMediaItem item) {
  final relativePath = _normalizeRelativePath(item.relativePath);
  final volumeName = _volumeNameFromMediaKey(item.mediaKey);
  if (volumeName == 'external' || volumeName == 'external_primary') {
    return relativePath;
  }
  return 'Storage/${_safeVolumeSegment(volumeName)}/$relativePath';
}

String _volumeNameFromMediaKey(String mediaKey) {
  final separator = mediaKey.lastIndexOf(':');
  if (separator <= 0 || separator == mediaKey.length - 1) {
    throw FormatException('Invalid MediaStore media key: $mediaKey');
  }
  return mediaKey.substring(0, separator);
}

final _unsafeVolumeCharacters = RegExp(r'[^A-Za-z0-9_-]');
final _windowsReservedName = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
  caseSensitive: false,
);

String _safeVolumeSegment(String volumeName) {
  var safeName = volumeName.replaceAll(_unsafeVolumeCharacters, '_');
  var wasSanitized = safeName != volumeName;
  if (safeName.isEmpty) {
    safeName = 'volume';
    wasSanitized = true;
  }
  if (_windowsReservedName.hasMatch(safeName)) {
    wasSanitized = true;
  }
  if (!wasSanitized) {
    return safeName;
  }

  // The suffix prevents distinct invalid names that sanitize to the same
  // Windows-safe segment from sharing a backup destination.
  return '${safeName}_${_stableVolumeHash(volumeName)}';
}

String _stableVolumeHash(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _normalizeRelativePath(String value) {
  final normalized = value.replaceAll(r'\', '/');
  final segments = normalized
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
  if (segments.any((segment) => segment == '..')) {
    throw FormatException('Unsafe MediaStore relative path: $value');
  }
  return segments.isEmpty ? '' : '${segments.join('/')}/';
}

FileType _fileType(android_channel.BackupMediaItem item) {
  if (item.mimeType.startsWith('image/')) {
    return FileType.image;
  }
  if (item.mimeType.startsWith('video/')) {
    return FileType.video;
  }
  return item.displayName.guessFileType();
}
