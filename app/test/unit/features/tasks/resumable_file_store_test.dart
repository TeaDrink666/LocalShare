import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:localsend_app/features/tasks/resumable_file_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late ResumableFileStore store;
  final bytes = [1, 2, 3, 4, 5, 6];
  final hash = sha256.convert(bytes).toString();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('localshare-resume-');
    store = ResumableFileStore(root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('restores a durable offset and removes an unacknowledged tail', () async {
    await store.append(
        key: 'file', size: 6, hash: hash, offset: 0, bytes: bytes.take(3).toList(), chunkHash: sha256.convert(bytes.take(3).toList()).toString());
    await store.dataFile('file').writeAsBytes([9, 9], mode: FileMode.append);
    store = ResumableFileStore(root);
    expect((await store.status('file', 6, hash))['offset'], 3);
    await store.append(
        key: 'file', size: 6, hash: hash, offset: 3, bytes: bytes.skip(3).toList(), chunkHash: sha256.convert(bytes.skip(3).toList()).toString());
    expect(await store.dataFile('file').readAsBytes(), bytes);
  });
  test('rejects stale offsets and changed source contents', () async {
    await store.append(key: 'file', size: 6, hash: hash, offset: 0, bytes: [1, 2, 3], chunkHash: sha256.convert([1, 2, 3]).toString());
    await expectLater(
        store.append(key: 'file', size: 6, hash: hash, offset: 0, bytes: [1], chunkHash: sha256.convert([1]).toString()), throwsFormatException);
    await expectLater(store.status('file', 6, '0' * 64), throwsFormatException);
  });
  test('a bad chunk never advances the checkpoint', () async {
    await expectLater(store.append(key: 'file', size: 6, hash: hash, offset: 0, bytes: [1, 2, 3], chunkHash: '0' * 64), throwsFormatException);
    expect((await store.status('file', 6, hash))['offset'], 0);
  });
  test('recovers publication when the process died before final acknowledgement', () async {
    await store.append(key: 'file', size: 6, hash: hash, offset: 0, bytes: bytes, chunkHash: hash);
    final saved = File(p.join(root.path, 'original.bin'));
    await store.publishing('file', 6, hash, saved.path);
    await saved.writeAsBytes(bytes);
    store = ResumableFileStore(root);
    expect((await store.status('file', 6, hash))['committed'], isTrue);
    expect(await store.dataFile('file').exists(), isFalse);
    await saved.writeAsBytes([6, 5, 4, 3, 2, 1]);
    await expectLater(store.status('file', 6, hash), throwsFormatException);
  });
  test('isolates identical names across different tasks', () {
    expect(store.key('peer', 'task1', 'file'), isNot(store.key('peer', 'task2', 'file')));
  });
  test('a fully checkpointed file can finish publication with an empty chunk', () async {
    await store.append(key: 'file', size: 6, hash: hash, offset: 0, bytes: bytes, chunkHash: hash);
    store = ResumableFileStore(root);
    expect(await store.append(key: 'file', size: 6, hash: hash, offset: 6, bytes: const [], chunkHash: sha256.convert([]).toString()), 6);
    expect(await store.dataFile('file').readAsBytes(), bytes);
  });
}
