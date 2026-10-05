import 'dart:io';
import 'package:localsend_app/features/tasks/task_destination.dart';
import 'package:localsend_app/util/native/publish_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('preserves project relative paths and Unicode names', () {
    expect(() => validateTaskPaths(['项目/src/main.dart', '项目/pubspec.yaml'], operatingSystem: 'windows'), returnsNormally);
  });
  test('rejects duplicate paths, case collisions and file-directory collisions', () {
    for (final paths in [
      ['src/a.dart', 'src/a.dart'],
      ['src/A.dart', 'src/a.dart'],
      ['src', 'src/a.dart']
    ]) {
      expect(() => validateTaskPaths(paths, operatingSystem: 'windows'), throwsFormatException);
    }
  });
  test('rejects invalid names and traversal instead of silently renaming', () {
    for (final path in ['../a.dart', '/a.dart', 'src\\a.dart', 'src/a?.dart', 'src//a.dart']) {
      expect(() => validateTaskPaths([path], operatingSystem: 'windows'), throwsFormatException);
    }
  });
  test('publishing does not overwrite an existing destination', () async {
    final root = await Directory.systemTemp.createTemp('localshare-publish-');
    addTearDown(() => root.delete(recursive: true));
    final source = await File(p.join(root.path, 'source.part')).writeAsString('new');
    final existing = await File(p.join(root.path, 'original.txt')).writeAsString('original');
    await expectLater(publishFileWithoutReplacing(source, existing.path), throwsA(isA<FileSystemException>()));
    expect(await existing.readAsString(), 'original');
    expect(await source.readAsString(), 'new');
  });
  test('a verified file is published at its unchanged name', () async {
    final root = await Directory.systemTemp.createTemp('localshare-publish-');
    addTearDown(() => root.delete(recursive: true));
    final source = await File(p.join(root.path, 'source.part')).writeAsString('content');
    final target = p.join(root.path, '文件.dart');
    await publishFileWithoutReplacing(source, target);
    expect(await File(target).readAsString(), 'content');
    expect(await source.exists(), isFalse);
  });
}
