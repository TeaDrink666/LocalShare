import 'dart:collection';
import 'dart:convert';

/// A source path that needs a safe, unique name inside a downloaded archive.
final class ArchivePathSource {
  const ArchivePathSource({
    required this.id,
    required this.relativePath,
  });

  final String id;
  final String relativePath;
}

/// Produces deterministic Windows-safe ZIP paths keyed by source ID.
///
/// `/` remains the directory separator. Characters Windows cannot extract,
/// trailing dots/spaces, and reserved device names are made safe per segment.
/// If distinct source paths collapse to the same case-insensitive Windows
/// path, every member of that collision group receives a stable hash suffix.
Map<String, String> createWindowsSafeArchivePaths(
  Iterable<ArchivePathSource> sources,
) {
  final candidates = <_ArchivePathCandidate>[];
  final sourceIds = <String>{};
  final groups = <String, List<_ArchivePathCandidate>>{};

  for (final source in sources) {
    if (!sourceIds.add(source.id)) {
      throw ArgumentError.value(
        source.id,
        'sources',
        'Archive path source IDs must be unique.',
      );
    }
    final candidate = _ArchivePathCandidate(
      source: source,
      sanitizedPath: _sanitizeRelativePath(source.relativePath),
    );
    candidates.add(candidate);
    groups
        .putIfAbsent(_windowsPathKey(candidate.sanitizedPath), () => [])
        .add(candidate);
  }

  final result = <String, String>{};
  final usedWindowsPaths = <String>{};

  // Reserve non-colliding names first. A generated suffix must not take a
  // natural name belonging to a different source.
  for (final candidate in candidates) {
    final group = groups[_windowsPathKey(candidate.sanitizedPath)]!;
    if (group.length == 1) {
      result[candidate.source.id] = candidate.sanitizedPath;
      usedWindowsPaths.add(_windowsPathKey(candidate.sanitizedPath));
    }
  }

  final collisionKeys = groups.keys
      .where((key) => groups[key]!.length > 1)
      .toList(growable: false)
    ..sort();
  for (final collisionKey in collisionKeys) {
    final group = [...groups[collisionKey]!]..sort((left, right) {
        final pathComparison =
            left.source.relativePath.compareTo(right.source.relativePath);
        if (pathComparison != 0) {
          return pathComparison;
        }
        return left.source.id.compareTo(right.source.id);
      });

    for (final candidate in group) {
      var attempt = 0;
      late String uniquePath;
      while (true) {
        final hashInput = attempt == 0
            ? candidate.source.relativePath
            : '${candidate.source.relativePath}\u0000'
                '${candidate.source.id}\u0000$attempt';
        uniquePath = _appendStableSuffix(
          candidate.sanitizedPath,
          '~${_fnv1a32(hashInput)}',
        );
        if (usedWindowsPaths.add(_windowsPathKey(uniquePath))) {
          break;
        }
        attempt++;
      }
      result[candidate.source.id] = uniquePath;
    }
  }

  return UnmodifiableMapView(result);
}

String _sanitizeRelativePath(String path) =>
    path.split('/').map(_sanitizeSegment).join('/');

String _sanitizeSegment(String segment) {
  var sanitized = segment.replaceAll(_invalidWindowsCharacter, '_');
  sanitized = sanitized.replaceAllMapped(_trailingWindowsCharacter, (match) {
    return List.filled(match.group(0)!.length, '_').join();
  });
  if (sanitized.isEmpty) {
    sanitized = '_';
  }

  final firstDot = sanitized.indexOf('.');
  final rawDeviceName =
      firstDot == -1 ? sanitized : sanitized.substring(0, firstDot);
  final deviceName = rawDeviceName.replaceFirst(RegExp(r'[ .]+$'), '');
  if (_windowsReservedDeviceName.hasMatch(deviceName)) {
    sanitized = '_$sanitized';
  }
  return sanitized;
}

String _windowsPathKey(String path) => path.toLowerCase();

String _appendStableSuffix(String path, String suffix) {
  final separator = path.lastIndexOf('/');
  final directory = separator == -1 ? '' : path.substring(0, separator + 1);
  final fileName = separator == -1 ? path : path.substring(separator + 1);
  final extensionStart = fileName.lastIndexOf('.');
  if (extensionStart <= 0) {
    return '$directory$fileName$suffix';
  }
  return '$directory${fileName.substring(0, extensionStart)}'
      '$suffix${fileName.substring(extensionStart)}';
}

String _fnv1a32(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

final _invalidWindowsCharacter = RegExp(r'[<>:"|?*\\\x00-\x1f]');
final _trailingWindowsCharacter = RegExp(r'[ .]+$');
final _windowsReservedDeviceName = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
  caseSensitive: false,
);

final class _ArchivePathCandidate {
  const _ArchivePathCandidate({
    required this.source,
    required this.sanitizedPath,
  });

  final ArchivePathSource source;
  final String sanitizedPath;
}
