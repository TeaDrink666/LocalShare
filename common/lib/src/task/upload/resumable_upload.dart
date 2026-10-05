import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:common/api_route_builder.dart';
import 'package:common/model/device.dart';
import 'package:common/src/isolate/child/http_provider.dart';
import 'package:crypto/crypto.dart';

const resumableChunkSize = 8 * 1024 * 1024;

Future<void> uploadResumable(
    {required CustomHttpClient client,
    required Device device,
    required String sessionId,
    required String fileId,
    required String token,
    required int size,
    required Stream<List<int>> Function(int start, int? end) openSource,
    required CustomCancelToken cancelToken,
    required void Function(double) onProgress}) async {
  void checkCanceled() {
    if (cancelToken.isCanceled) throw StateError('Task paused or canceled');
  }

  var sourceSize = 0;
  final hash = (await sha256
          .bind(openSource(0, null).map((data) {
            checkCanceled();
            sourceSize += data.length;
            return data;
          }))
          .first)
      .toString();
  if (sourceSize != size) throw const FormatException('源文件大小已改变，请创建新任务');
  checkCanceled();
  final uploadUrl = ApiRoute.upload.target(device);
  final base = uploadUrl.substring(0, uploadUrl.indexOf('/api/'));
  final query = {'sessionId': sessionId, 'fileId': fileId, 'token': token, 'sha256': hash};
  final state =
      jsonDecode(await client.get(uri: '$base/api/localshare/v1/transfer/status', query: query, cancelToken: cancelToken)) as Map<String, dynamic>;
  if (state['committed'] == true) {
    onProgress(1);
    return;
  }
  var offset = state['offset'] as int;
  if (offset < 0 || offset > size) {
    throw const FormatException('Invalid receiver offset');
  }
  onProgress(size == 0 ? 0 : offset / size);
  final source = StreamIterator(openSource(offset, null));
  List<int> pending = const [];
  var pendingStart = 0;
  try {
    do {
      checkCanceled();
      final end = (offset + resumableChunkSize).clamp(0, size);
      final builder = BytesBuilder(copy: false);
      while (builder.length < end - offset) {
        checkCanceled();
        if (pendingStart == pending.length) {
          if (!await source.moveNext()) break;
          pending = source.current;
          pendingStart = 0;
        }
        final length = (end - offset - builder.length).clamp(0, pending.length - pendingStart);
        builder.add(pending.sublist(pendingStart, pendingStart + length));
        pendingStart += length;
      }
      final chunk = builder.takeBytes();
      if (chunk.length != end - offset) throw const FormatException('源文件大小已改变');
      await client.postStream(
          uri: '$base/api/localshare/v1/transfer/chunk',
          query: {...query, 'offset': '$offset'},
          headers: {
            'Content-Length': '${chunk.length}',
            'Content-Type': 'application/octet-stream',
            'x-localshare-chunk-sha256': sha256.convert(chunk).toString()
          },
          stream: Stream.value(chunk),
          cancelToken: cancelToken,
          onSendProgress: (progress) => onProgress(size == 0 ? 0 : (offset + chunk.length * progress) / size));
      offset = end;
      onProgress(size == 0 ? 1 : offset / size);
    } while (offset < size);
  } finally {
    await source.cancel();
  }
}

Stream<List<int>> byteRange(Stream<List<int>> source, int start, int? end) async* {
  var position = 0;
  await for (final data in source) {
    final next = position + data.length;
    if (next > start && (end == null || position < end)) {
      final from = (start - position).clamp(0, data.length);
      final to = end == null ? data.length : (end - position).clamp(0, data.length);
      if (to > from) yield data.sublist(from, to);
    }
    position = next;
    if (end != null && position >= end) break;
  }
}
