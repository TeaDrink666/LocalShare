import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/file_saver.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('localshare-path-test-');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('接收根目录不存在时会先创建目录', () async {
    final destinationRoot =
        path.join(temporaryDirectory.path, 'missing', 'Downloads');

    final (destinationPath, documentUri, finalName) =
        await digestFilePathAndPrepareDirectory(
      parentDirectory: destinationRoot,
      fileName: 'photo.jpg',
      createdDirectories: {},
    );

    expect(await Directory(destinationRoot).exists(), isTrue);
    expect(destinationPath, path.join(destinationRoot, 'photo.jpg'));
    expect(documentUri, isNull);
    expect(finalName, 'photo.jpg');
  });

  test('嵌套文件使用当前平台的路径拼接', () async {
    final destinationRoot = path.join(temporaryDirectory.path, 'Downloads');

    final (destinationPath, _, _) = await digestFilePathAndPrepareDirectory(
      parentDirectory: destinationRoot,
      fileName: 'Pictures/Screenshots/photo.jpg',
      createdDirectories: {},
    );

    expect(
      destinationPath,
      path.join(
        destinationRoot,
        'Pictures',
        'Screenshots',
        'photo.jpg',
      ),
    );
    expect(path.isWithin(destinationRoot, destinationPath), isTrue);
  });

  test('拒绝跳出接收根目录的相对路径', () async {
    final destinationRoot = path.join(temporaryDirectory.path, 'Downloads');

    expect(
      () => digestFilePathAndPrepareDirectory(
        parentDirectory: destinationRoot,
        fileName: '../outside.txt',
        createdDirectories: {},
      ),
      throwsA('Path traversal detected'),
    );
  });
}
