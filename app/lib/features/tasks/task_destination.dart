import 'dart:io';
import 'package:legalize/legalize.dart';
import 'package:path/path.dart' as p;

/// Validate the complete manifest before receiving any bytes. Names are never
/// silently rewritten and two files cannot claim one relative destination.
void validateTaskPaths(Iterable<String> paths, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  final seen = <String>{};
  for (final path in paths) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
      throw FormatException('不支持的相对路径: $path');
    }
    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..' || legalizeFilename(segment, os: os) != segment) {
        throw FormatException('目标系统无法保留此文件名: $path');
      }
    }
    final comparison = os == 'windows' || os == 'macos' ? path.toLowerCase() : path;
    if (!seen.add(comparison)) {
      throw FormatException('任务内存在重复路径: $path，请拆分任务或选择上级文件夹');
    }
  }
  for (final path in seen) {
    final segments = path.split('/');
    for (var i = 1; i < segments.length; i++) {
      if (seen.contains(segments.take(i).join('/'))) {
        throw FormatException('文件与目录冲突: $path');
      }
    }
  }
}

String taskDirectoryName(String id, DateTime created) {
  final date = created.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
  return '接收_${date}_${id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').substring(0, 8)}';
}

Future<String> taskFilePath(String directory, String relativePath) async {
  validateTaskPaths([relativePath]);
  final path = p.joinAll([directory, ...relativePath.split('/')]);
  if (!p.isWithin(directory, path)) {
    throw const FormatException('Invalid relative path');
  }
  if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound) {
    throw FileSystemException('目标文件已存在，保留原名需要创建新任务', path);
  }
  // Reject existing symlink parents, which could escape the task directory.
  var parent = p.dirname(path);
  while (parent == directory || p.isWithin(directory, parent)) {
    if (await FileSystemEntity.type(parent, followLinks: false) == FileSystemEntityType.link) {
      throw FileSystemException('任务路径包含链接', parent);
    }
    parent = p.dirname(parent);
  }
  await Directory(p.dirname(path)).create(recursive: true);
  return path;
}
