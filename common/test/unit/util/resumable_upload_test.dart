import 'dart:async';
import 'dart:convert';
import 'package:common/model/device.dart';
import 'package:common/src/isolate/child/http_provider.dart';
import 'package:common/src/task/upload/resumable_upload.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const peer = Device(
    ip: '127.0.0.1',
    version: '2.1',
    port: 53317,
    https: false,
    fingerprint: 'peer',
    alias: 'Peer',
    deviceModel: null,
    deviceType: DeviceType.desktop,
    download: false);

class ReceiverClient extends CustomHttpClient {
  ReceiverClient(this.offset, {this.committed = false});
  int offset;
  final bool committed;
  final chunks = <List<int>>[];
  @override
  Future<String> get({required String uri, required Map<String, String> query, CustomCancelToken? cancelToken}) async =>
      jsonEncode({'offset': offset, 'committed': committed});
  @override
  Future<String> post({required String uri, Map<String, String> query = const {}, required Map<String, dynamic> json}) async =>
      throw UnimplementedError();
  @override
  Future<void> postStream(
      {required String uri,
      required Map<String, String> query,
      required Map<String, String> headers,
      required Stream<List<int>> stream,
      required void Function(double) onSendProgress,
      required CustomCancelToken cancelToken}) async {
    expect(int.parse(query['offset']!), offset);
    final bytes = await stream.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    expect(sha256.convert(bytes).toString(), headers['x-localshare-chunk-sha256']);
    chunks.add(bytes);
    offset += bytes.length;
    onSendProgress(1);
  }
}

void main() {
  test('pause cancels a pending receiver status query', () async {
    final client = BlockingReceiver();
    final token = CustomCancelToken();
    final upload = uploadResumable(
        client: client,
        device: peer,
        sessionId: 'task',
        fileId: 'file',
        token: 'token',
        size: 3,
        cancelToken: token,
        onProgress: (_) {},
        openSource: (start, end) => Stream.value([1, 2, 3]));
    await client.entered.future;
    token.cancel();
    await expectLater(upload, throwsStateError);
  });
  test('continues at the receiver offset and opens the source only twice', () async {
    final bytes = List<int>.generate(resumableChunkSize + 5, (index) => index % 256);
    final client = ReceiverClient(3);
    var reads = 0;
    var progress = 0.0;
    await uploadResumable(
        client: client,
        device: peer,
        sessionId: 'task',
        fileId: 'file',
        token: 'token',
        size: bytes.length,
        cancelToken: CustomCancelToken(),
        onProgress: (value) => progress = value,
        openSource: (start, end) {
          reads++;
          return Stream.fromIterable([
            bytes.sublist(start, (start + 2).clamp(0, bytes.length)),
            bytes.sublist((start + 2).clamp(0, bytes.length), end ?? bytes.length),
          ]);
        });
    expect(client.offset, bytes.length);
    expect(client.chunks, hasLength(2));
    expect(client.chunks.expand((chunk) => chunk), bytes.skip(3));
    expect(reads, 2);
    expect(progress, 1);
  });
  test('an already published file is not uploaded again', () async {
    final client = ReceiverClient(3, committed: true);
    await uploadResumable(
        client: client,
        device: peer,
        sessionId: 'task',
        fileId: 'file',
        token: 'token',
        size: 3,
        cancelToken: CustomCancelToken(),
        onProgress: (_) {},
        openSource: (start, end) => Stream.value([1, 2, 3]));
    expect(client.chunks, isEmpty);
  });
  test('finishes a complete checkpoint with an empty final request', () async {
    final client = ReceiverClient(3);
    await uploadResumable(
        client: client,
        device: peer,
        sessionId: 'task',
        fileId: 'file',
        token: 'token',
        size: 3,
        cancelToken: CustomCancelToken(),
        onProgress: (_) {},
        openSource: (start, end) => Stream.value([1, 2, 3].sublist(start)));
    expect(client.chunks, [[]]);
  });
  test('changed source size is rejected before transmitting', () async {
    final client = ReceiverClient(0);
    await expectLater(
        uploadResumable(
            client: client,
            device: peer,
            sessionId: 'task',
            fileId: 'file',
            token: 'token',
            size: 2,
            cancelToken: CustomCancelToken(),
            onProgress: (_) {},
            openSource: (start, end) => Stream.value([1, 2, 3])),
        throwsFormatException);
    expect(client.chunks, isEmpty);
  });
}

class BlockingReceiver extends ReceiverClient {
  BlockingReceiver() : super(0);
  final entered = Completer<void>();
  @override
  Future<String> get({required String uri, required Map<String, String> query, CustomCancelToken? cancelToken}) {
    final response = Completer<String>();
    cancelToken!.setCancel(() => response.completeError(StateError('Canceled')));
    entered.complete();
    return response.future;
  }
}
