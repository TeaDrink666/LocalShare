import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final _logger = Logger('ContextMenuHelper');

const _windowsFileName = 'LocalShare';
const _legacyWindowsFileName = 'LocalSend';

Future<bool> enableContextMenu() async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    final created = await _createCurrentShortcut();
    if (created) {
      await _deleteOwnedLegacyShortcut();
    }
    return created;
  } catch (error) {
    _logger.severe('Failed to enable context menu: $error');
    return false;
  }
}

Future<bool> disableContextMenu() async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    final current = File(_getWindowsFilePath(_windowsFileName));
    if (await current.exists()) {
      await current.delete();
    }
    await _deleteOwnedLegacyShortcut();
    return true;
  } catch (error) {
    _logger.warning('Failed to disable context menu', error);
    return false;
  }
}

Future<bool> isContextMenuEnabled() async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  try {
    final current = File(_getWindowsFilePath(_windowsFileName));
    if (await current.exists()) {
      // A portable build may have moved since the shortcut was created. Rebuild
      // it instead of trusting a stale TargetPath left by an older package.
      return await _createCurrentShortcut();
    }

    final legacy = File(_getWindowsFilePath(_legacyWindowsFileName));
    if (!await legacy.exists()) {
      return false;
    }
    final target = await _readShortcutTarget(legacy.path);
    if (!_isOwnedLegacyTarget(target)) {
      // Never rename or delete an independently installed LocalSend shortcut.
      return false;
    }

    final migrated = await _createCurrentShortcut();
    if (migrated) {
      await legacy.delete();
    }
    return migrated;
  } catch (error) {
    _logger.warning('Failed to inspect context menu', error);
    return false;
  }
}

Future<bool> _createCurrentShortcut() async {
  final shortcutPath = _getWindowsFilePath(_windowsFileName);
  const script = r'''
$ErrorActionPreference = 'Stop'
$targetPath = $env:LOCALSHARE_SHORTCUT_TARGET
$shortcutFile = $env:LOCALSHARE_SHORTCUT_FILE
if ([string]::IsNullOrWhiteSpace($targetPath) -or [string]::IsNullOrWhiteSpace($shortcutFile)) {
  throw 'Missing LocalShare shortcut parameters.'
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutFile)
$shortcut.TargetPath = $targetPath
$shortcut.WorkingDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
$shortcut.Save()
''';
  final result = await Process.run(
    'powershell',
    const ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
    environment: {
      'LOCALSHARE_SHORTCUT_TARGET': Platform.resolvedExecutable,
      'LOCALSHARE_SHORTCUT_FILE': shortcutPath,
    },
  );
  if (result.exitCode != 0) {
    throw Exception('Failed to create shortcut: ${result.stderr}');
  }
  return await File(shortcutPath).exists();
}

Future<String?> _readShortcutTarget(String shortcutPath) async {
  const script = r'''
$ErrorActionPreference = 'Stop'
$shortcutFile = $env:LOCALSHARE_SHORTCUT_FILE
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutFile)
[Console]::Out.Write($shortcut.TargetPath)
''';
  final result = await Process.run(
    'powershell',
    const ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
    environment: {'LOCALSHARE_SHORTCUT_FILE': shortcutPath},
  );
  if (result.exitCode != 0) {
    _logger.warning('Failed to read shortcut target: ${result.stderr}');
    return null;
  }
  final target = result.stdout.toString().trim();
  return target.isEmpty ? null : target;
}

Future<void> _deleteOwnedLegacyShortcut() async {
  final legacy = File(_getWindowsFilePath(_legacyWindowsFileName));
  if (!await legacy.exists()) {
    return;
  }
  final target = await _readShortcutTarget(legacy.path);
  if (_isOwnedLegacyTarget(target)) {
    await legacy.delete();
  }
}

bool _isOwnedLegacyTarget(String? target) {
  if (target == null || target.trim().isEmpty) {
    return false;
  }
  final normalizedTarget = _normalizeWindowsPath(target);
  final currentExecutable = _normalizeWindowsPath(Platform.resolvedExecutable);
  if (normalizedTarget == currentExecutable) {
    return true;
  }

  // Older development ZIPs kept the upstream executable name but were placed
  // in a LocalShare-labelled directory. This distinguishes them from an
  // independent LocalSend installation, which must remain untouched.
  return normalizedTarget.contains(r'\localshare');
}

String _normalizeWindowsPath(String value) =>
    value.trim().replaceAll('/', r'\').toLowerCase();

String _getWindowsFilePath(String appName) {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    throw StateError('APPDATA is unavailable.');
  }
  return '$appData/Microsoft/Windows/SendTo/$appName.lnk';
}
