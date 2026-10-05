import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/util/native/content_uri_helper.dart';
import 'package:logging/logging.dart';

part 'android_channel.mapper.dart';

const _methodChannel = MethodChannel('org.localsend.localsend_app/localsend');
final _logger = Logger('AndroidSaf');

/// From Android 10 and above, we need to use the Storage Access Framework (SAF) to access files due to the scoped storage.
/// SAF itself is available from Android 4.4 (API level 19).
/// We implemented our own algorithm to build encode and decode content URIs.
/// Older versions might also work but the encoded content URI is not guaranteed to work with our algorithm.
const contentUriMinSdk = 27;

Future<PickDirectoryResult?> pickDirectoryAndroid() async {
  final result = await _methodChannel.invokeMethod<Map>('pickDirectory');
  if (result == null) {
    return null;
  }

  return PickDirectoryResultMapper.fromJson({
    'directoryUri': result['directoryUri'],
    'files': (result['files'] as List).map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList(),
  });
}

Future<String?> pickDirectoryPathAndroid() async {
  final result = await _methodChannel.invokeMethod<String>('pickDirectoryPath');
  return result;
}

Future<List<FileInfo>?> pickFilesAndroid() async {
  final result = await _methodChannel.invokeMethod<List>('pickFiles');
  if (result == null) {
    return null;
  }

  return result.map((e) => FileInfoMapper.fromJson((e as Map).cast<String, dynamic>())).toList();
}

Future<void> createDirectory({
  required String documentUri,
  required String directoryName,
}) async {
  _logger.info('Creating directory "$directoryName" in $documentUri');
  await _methodChannel.invokeMethod('createDirectory', {
    'documentUri': documentUri,
    'directoryName': directoryName,
  });
}

/// Deletes only the document URI returned when creating this task's file.
Future<void> deleteTaskDocument(String uri) async {
  await _methodChannel.invokeMethod('deleteTaskDocument', {'uri': uri});
}

Future<void> createMissingDirectoriesAndroid({
  required String parentUri,
  required String fileName,
  required Set<String> createdDirectories,
}) async {
  final parts = fileName.split('/');
  for (int i = 0; i < parts.length - 1; i++) {
    final subDirPath = parts.sublist(0, i + 1).join('/');
    if (createdDirectories.contains(subDirPath)) {
      continue;
    }

    await createDirectory(
      documentUri: ContentUriHelper.convertTreeUriToDocumentUri(
        treeUri: parentUri,
        suffix: i == 0 ? null : parts.sublist(0, i).join('/'),
      ),
      directoryName: parts[i],
    );
    createdDirectories.add(subDirPath);
  }
}

Future<void> openContentUri({
  required String uri,
}) async {
  _logger.info('Opening content URI: $uri');
  await _methodChannel.invokeMethod('openContentUri', {
    'uri': uri,
  });
}

Future<void> openGallery() async {
  _logger.info('Opening gallery');
  await _methodChannel.invokeMethod('openGallery');
}

Future<BackupMediaPage> scanBackupMedia({
  int afterId = 0,
  int limit = 250,
  bool includeImages = true,
  bool includeVideos = true,
}) async {
  if (afterId < 0) {
    throw ArgumentError.value(afterId, 'afterId', 'Must not be negative');
  }
  RangeError.checkValueInInterval(limit, 1, 1000, 'limit');

  final result = await _methodChannel.invokeMapMethod<Object?, Object?>(
    'scanBackupMedia',
    {
      'afterId': afterId,
      'limit': limit,
      'includeImages': includeImages,
      'includeVideos': includeVideos,
    },
  );
  if (result == null) {
    throw StateError('Android returned no media scan result');
  }
  return BackupMediaPage.fromMap(result);
}

@immutable
class BackupMediaItem {
  const BackupMediaItem({
    required this.mediaKey,
    required this.contentUri,
    required this.relativePath,
    required this.displayName,
    required this.sizeBytes,
    required this.modifiedAtSeconds,
    required this.generationModified,
    required this.mimeType,
  });

  factory BackupMediaItem.fromMap(Map<Object?, Object?> map) {
    return BackupMediaItem(
      mediaKey: _requiredString(map, 'mediaKey'),
      contentUri: _requiredString(map, 'contentUri'),
      relativePath: _requiredString(map, 'relativePath'),
      displayName: _requiredString(map, 'displayName'),
      sizeBytes: _requiredInt(map, 'sizeBytes'),
      modifiedAtSeconds: _requiredInt(map, 'modifiedAtSeconds'),
      generationModified: _nullableInt(map, 'generationModified'),
      mimeType: _requiredString(map, 'mimeType'),
    );
  }

  final String mediaKey;
  final String contentUri;
  final String relativePath;
  final String displayName;
  final int sizeBytes;
  final int modifiedAtSeconds;
  final int? generationModified;
  final String mimeType;
}

@immutable
class BackupMediaPage {
  const BackupMediaPage({
    required this.items,
    required this.nextAfterId,
    required this.hasMore,
  });

  factory BackupMediaPage.fromMap(Map<Object?, Object?> map) {
    final rawItems = map['items'];
    if (rawItems is! List) {
      throw const FormatException('Expected "items" to be a list');
    }

    return BackupMediaPage(
      items: List<BackupMediaItem>.unmodifiable(
        rawItems.map((item) {
          if (item is! Map) {
            throw const FormatException('Expected a media item map');
          }
          return BackupMediaItem.fromMap(item.cast<Object?, Object?>());
        }),
      ),
      nextAfterId: _requiredInt(map, 'nextAfterId'),
      hasMore: _requiredBool(map, 'hasMore'),
    );
  }

  final List<BackupMediaItem> items;
  final int nextAfterId;
  final bool hasMore;
}

String _requiredString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected "$key" to be a string');
}

int _requiredInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected "$key" to be an integer');
}

int? _nullableInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw FormatException('Expected "$key" to be an integer or null');
}

bool _requiredBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected "$key" to be a boolean');
}

@MappableClass()
class PickDirectoryResult with PickDirectoryResultMappable {
  final String directoryUri;
  final List<FileInfo> files;

  PickDirectoryResult({
    required this.directoryUri,
    required this.files,
  });
}

@MappableClass()
class FileInfo with FileInfoMappable {
  final String name;
  final int size;
  final String uri;
  final int lastModified;

  FileInfo({
    required this.name,
    required this.size,
    required this.uri,
    required this.lastModified,
  });
}
