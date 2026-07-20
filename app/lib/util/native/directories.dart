import 'dart:io' show Directory, FileSystemException, Platform;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path;
import 'package:shared_storage/shared_storage.dart' as shared_storage;

final _windowsPath = p.Context(style: p.Style.windows);

Future<String> getDefaultDestinationDirectory() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      // ignore: deprecated_member_use
      final dir = await shared_storage.getExternalStoragePublicDirectory(
        // ignore: deprecated_member_use
        shared_storage.EnvironmentDirectory.downloads,
      );
      return dir?.path ?? '/storage/emulated/0/Download';
    case TargetPlatform.iOS:
      return (await path.getApplicationDocumentsDirectory()).path;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.fuchsia:
      var downloadDir = await path.getDownloadsDirectory();
      if (downloadDir == null) {
        final home = Platform.environment['HOME'];
        if (home != null && home.trim().isNotEmpty) {
          downloadDir = Directory(p.join(home, 'Downloads'));
        } else {
          downloadDir = await path.getApplicationDocumentsDirectory();
        }
      }
      return p.normalize(downloadDir.path);
    case TargetPlatform.windows:
      return _getWindowsDefaultDestinationDirectory();
  }
}

/// Returns the default root for phone media backups.
///
/// This is deliberately a child directory rather than the ordinary receive
/// root, so backup media never mixes with one-off file transfers by default.
Future<String> getDefaultBackupDestinationDirectory() async {
  return p.join(await getDefaultDestinationDirectory(), 'LocalShare Backup');
}

/// Returns fully-qualified Windows destination candidates in preference order.
///
/// `HOMEPATH` is deliberately never used by itself. On Windows it commonly
/// contains only `\Users\name`, so treating it as a complete path makes the
/// result depend on the drive from which LocalShare was launched.
@visibleForTesting
List<String> buildWindowsDestinationDirectoryCandidates({
  required String? downloadsDirectory,
  required String? documentsDirectory,
  required Map<String, String> environment,
}) {
  final candidates = <String?>[
    downloadsDirectory,
    _joinWindowsPath(environment['USERPROFILE'], 'Downloads'),
    _windowsHomeFromDriveAndPath(environment),
    documentsDirectory == null ? null : _joinWindowsPath(documentsDirectory, 'LocalShare'),
  ];

  final result = <String>[];
  for (final candidate in candidates) {
    if (candidate == null || !_isFullyQualifiedWindowsPath(candidate)) {
      continue;
    }

    final normalized = _windowsPath.normalize(candidate);
    if (!result.any((existing) => _windowsPath.equals(existing, normalized))) {
      result.add(normalized);
    }
  }
  return result;
}

Future<String> _getWindowsDefaultDestinationDirectory() async {
  Directory? downloadsDirectory;
  Directory? documentsDirectory;

  try {
    downloadsDirectory = await path.getDownloadsDirectory();
  } catch (_) {
    // Continue with the environment and Documents known-folder fallbacks.
  }

  try {
    documentsDirectory = await path.getApplicationDocumentsDirectory();
  } catch (_) {
    // USERPROFILE is available in normal Windows desktop sessions.
  }

  final candidates = buildWindowsDestinationDirectoryCandidates(
    downloadsDirectory: downloadsDirectory?.path,
    documentsDirectory: documentsDirectory?.path,
    environment: Platform.environment,
  );

  for (final candidate in candidates) {
    try {
      final directory = await Directory(candidate).create(recursive: true);
      return _windowsPath.normalize(directory.path);
    } catch (_) {
      // Try the next fully-qualified, user-writable directory.
    }
  }

  throw FileSystemException(
    'Could not resolve a writable Windows destination directory.',
  );
}

String? _windowsHomeFromDriveAndPath(Map<String, String> environment) {
  final homePath = environment['HOMEPATH'];
  if (homePath == null || homePath.trim().isEmpty) {
    return null;
  }

  if (_isFullyQualifiedWindowsPath(homePath)) {
    return _windowsPath.join(homePath, 'Downloads');
  }

  final homeDrive = environment['HOMEDRIVE'];
  if (homeDrive == null || !RegExp(r'^[A-Za-z]:$').hasMatch(homeDrive)) {
    return null;
  }
  return _windowsPath.join('$homeDrive\\', homePath, 'Downloads');
}

String? _joinWindowsPath(String? root, String child) {
  if (root == null || root.trim().isEmpty) {
    return null;
  }
  return _windowsPath.join(root, child);
}

bool _isFullyQualifiedWindowsPath(String value) {
  final path = value.trim();
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
}

String normalizeDestinationDirectory(String destinationDirectory) {
  if (destinationDirectory.startsWith('content://')) {
    return destinationDirectory;
  }
  return p.normalize(destinationDirectory);
}

Future<String> getCacheDirectory() async {
  return (await path.getTemporaryDirectory()).path;
}
