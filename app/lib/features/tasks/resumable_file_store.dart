import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const transferChunkSize = 8 * 1024 * 1024;

/// Durable checkpoints are acknowledged only after file flush and metadata
/// replacement. A retry truncates any unacknowledged tail left by a crash.
class ResumableFileStore {
  ResumableFileStore(this.directory);
  final Directory directory;
  final _locks = <String, Future<void>>{};

  String key(String peer, String task, String file) => sha256.convert(utf8.encode(jsonEncode([peer, task, file]))).toString();
  File dataFile(String key) => File(p.join(directory.path, '$key.part'));
  File _metadata(String key) => File(p.join(directory.path, '$key.json'));

  Future<Map<String, dynamic>> status(String key, int size, String hash) async {
    await directory.create(recursive: true);
    final metadata = _metadata(key);
    if (!await metadata.exists()) {
      return {'size': size, 'sha256': hash, 'offset': 0, 'committed': false};
    }
    final state = jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    if (state['size'] != size || state['sha256'] != hash) {
      throw const FormatException('源文件已改变，请创建新任务');
    }
    if (state['committed'] != true && state['publishingPath'] is String) {
      final published = File(state['publishingPath'] as String);
      if (await published.exists() && await published.length() == size && (await sha256.bind(published.openRead()).first).toString() == hash) {
        state['committed'] = true;
        state['path'] = published.path;
        await _save(key, state);
        if (await dataFile(key).exists()) await dataFile(key).delete();
      }
    }
    if (state['committed'] == true) {
      final saved = File(state['path'] as String);
      if (!await saved.exists() || await saved.length() != size || (await sha256.bind(saved.openRead()).first).toString() != hash) {
        throw const FormatException('已接收文件已被修改或移除，请创建新任务');
      }
    } else {
      final partial = dataFile(key);
      final offset = state['offset'] as int;
      if (offset > 0 && (!await partial.exists() || await partial.length() < offset)) {
        throw const FormatException('续传数据不完整，请重新开始任务');
      }
    }
    return state;
  }

  Future<int> append(
      {required String key,
      required int size,
      required String hash,
      required int offset,
      required List<int> bytes,
      required String chunkHash}) async {
    final previous = _locks[key] ?? Future.value();
    final completer = previous.catchError((Object _) {}).then((_) async {
      final state = await status(key, size, hash);
      if (state['committed'] == true) return size;
      if (offset != state['offset']) {
        throw FormatException('Offset mismatch: ${state['offset']}');
      }
      if (bytes.isEmpty && offset == size && size > 0) {
        if ((await sha256.bind(dataFile(key).openRead()).first).toString() != hash) {
          throw const FormatException('File checksum mismatch');
        }
        return size;
      }
      if (bytes.length > transferChunkSize || offset + bytes.length > size || (bytes.isEmpty && size != 0)) {
        throw const FormatException('Invalid chunk size');
      }
      if (sha256.convert(bytes).toString() != chunkHash) {
        throw const FormatException('Chunk checksum mismatch');
      }
      final file = dataFile(key);
      final output = await file.open(mode: FileMode.append);
      try {
        await output.truncate(offset);
        await output.setPosition(offset);
        await output.writeFrom(bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      final next = offset + bytes.length;
      if (next == size && (await sha256.bind(file.openRead()).first).toString() != hash) {
        await file.delete();
        if (await _metadata(key).exists()) await _metadata(key).delete();
        throw const FormatException('File checksum mismatch');
      }
      state['offset'] = next;
      await _save(key, state);
      return next;
    });
    final lock = completer.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    // The stored future is awaited by discard and by the next append.
    // ignore: unawaited_futures
    _locks[key] = lock;
    try {
      return await completer;
    } finally {
      if (identical(_locks[key], lock)) {
        unawaited(_locks.remove(key));
      }
    }
  }

  Future<void> commit(String key, int size, String hash, String path) async {
    final state = await status(key, size, hash);
    if (state['offset'] != size) throw StateError('Incomplete file');
    state['committed'] = true;
    state['path'] = path;
    await _save(key, state);
    if (await dataFile(key).exists()) await dataFile(key).delete();
  }

  Future<void> publishing(String key, int size, String hash, String path) async {
    final state = await status(key, size, hash);
    state['publishingPath'] = path;
    await _save(key, state);
  }

  Future<void> discard(String key) async {
    await (_locks[key] ?? Future.value());
    for (final file in [dataFile(key), _metadata(key)]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _save(String key, Map<String, dynamic> state) async {
    final temporary = File('${_metadata(key).path}.tmp');
    await temporary.writeAsString(jsonEncode(state), flush: true);
    await temporary.rename(_metadata(key).path);
  }
}
