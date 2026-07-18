import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:common/api_route_builder.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/file_type.dart';
import 'package:localsend_app/model/state/send/web/web_send_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_session.dart';
import 'package:localsend_app/model/state/send/web/web_send_state.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/provider/network/server/controller/send_controller.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/util/simple_server.dart';
import 'package:test/test.dart';
import 'package:uri_content/uri_content.dart';

void main() {
  group('web download route', () {
    test('returns an exact memory-backed byte range', () async {
      final harness = await _DownloadHarness.start(
        _webFile(bytes: List<int>.generate(10, (index) => index)),
      );
      addTearDown(harness.close);

      final response = await harness.download(range: 'bytes=2-5');

      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 2-5/10',
      );
      expect(response.contentLength, 4);
      expect(await _readBody(response), [2, 3, 4, 5]);
    });

    test('ignores malformed and multiple ranges', () async {
      final bytes = List<int>.generate(6, (index) => index);
      final harness = await _DownloadHarness.start(_webFile(bytes: bytes));
      addTearDown(harness.close);

      final response = await harness.download(range: 'bytes=0-1,4-5');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, bytes.length);
      expect(response.headers.value(HttpHeaders.contentRangeHeader), isNull);
      expect(await _readBody(response), bytes);
    });

    test('returns 416 for an unsatisfiable range', () async {
      final harness = await _DownloadHarness.start(
        _webFile(bytes: [0, 1, 2]),
      );
      addTearDown(harness.close);

      final response = await harness.download(range: 'bytes=3-');

      expect(
        response.statusCode,
        HttpStatus.requestedRangeNotSatisfiable,
      );
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */3',
      );
      expect(response.contentLength, 0);
      expect(await _readBody(response), isEmpty);
    });

    test('uses the actual disk file length and native file slicing', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'localshare-send-controller-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final diskFile =
          File('${tempDirectory.path}${Platform.pathSeparator}a.bin');
      await diskFile.writeAsBytes(List<int>.generate(7, (index) => index));

      final harness = await _DownloadHarness.start(
        _webFile(path: diskFile.path, reportedSize: 999),
      );
      addTearDown(harness.close);

      final response = await harness.download(range: 'bytes=-3');

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 4-6/7',
      );
      expect(await _readBody(response), [4, 5, 6]);
    });

    test('slices a known-length content URI across native chunks', () async {
      final uriContent = _FakeUriContent(
        length: 10,
        chunks: [
          [0, 1],
          [2, 3, 4, 5, 6],
          [7, 8, 9],
        ],
      );
      final harness = await _DownloadHarness.start(
        _webFile(path: 'content://media/external/file/42'),
        uriContent: uriContent,
      );
      addTearDown(harness.close);

      final response = await harness.download(range: 'bytes=3-7');

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 3-7/10',
      );
      expect(await _readBody(response), [3, 4, 5, 6, 7]);
      expect(uriContent.lengthRequests, 1);
      expect(uriContent.streamRequests, 1);
    });

    for (final unknownLength in <int?>[null, -1]) {
      test(
        'streams content URI length $unknownLength without range support',
        () async {
          final uriContent = _FakeUriContent(
            length: unknownLength,
            chunks: [
              [0, 1],
              [2, 3, 4],
            ],
          );
          final harness = await _DownloadHarness.start(
            _webFile(
              path: 'content://media/external/file/43',
              reportedSize: 999,
            ),
            uriContent: uriContent,
          );
          addTearDown(harness.close);

          final response = await harness.download(range: 'bytes=2-3');

          expect(response.statusCode, HttpStatus.ok);
          expect(
            response.headers.value(HttpHeaders.acceptRangesHeader),
            'none',
          );
          expect(
            response.headers.value(HttpHeaders.contentRangeHeader),
            isNull,
          );
          expect(response.contentLength, -1);
          expect(await _readBody(response), [0, 1, 2, 3, 4]);
        },
      );
    }
  });

  group('web download-all route', () {
    test('streams memory, disk, and unknown-length content URI files as ZIP',
        () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'localshare-download-all-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final diskBytes = [20, 21, 22, 23];
      final diskFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}report.txt',
      );
      await diskFile.writeAsBytes(diskBytes);

      final contentBytes = [30, 31, 32, 33, 34];
      final uriContent = _FakeUriContent(
        length: null,
        chunks: [
          contentBytes.sublist(0, 2),
          contentBytes.sublist(2),
        ],
      );
      final memoryBytes = [10, 11, 12];
      final harness = await _DownloadHarness.startFiles(
        {
          'photo': _webFile(
            id: 'photo',
            fileName: 'DCIM/相机/旅行/夏天🌻.jpg',
            bytes: memoryBytes,
          ),
          'document': _webFile(
            id: 'document',
            fileName: 'Documents/报告.txt',
            path: diskFile.path,
            reportedSize: 999,
          ),
          'video': _webFile(
            id: 'video',
            fileName: 'Movies/家庭/生日🎂.mp4',
            path: 'content://media/external/video/42',
            reportedSize: contentBytes.length,
          ),
        },
        uriContent: uriContent,
      );
      addTearDown(harness.close);

      final response = await harness.downloadAll();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'application/zip');
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'none');
      expect(
          response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
      expect(
        response.headers.value('content-disposition'),
        'attachment; filename="LocalShare-files.zip"; '
        "filename*=UTF-8''LocalShare-files.zip",
      );
      expect(response.contentLength, -1, reason: 'ZIP must remain chunked.');

      final archiveBytes = await _readBody(response);
      final archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
      expect(
        archive.files.map((file) => file.name),
        [
          'DCIM/相机/旅行/夏天🌻.jpg',
          'Documents/报告.txt',
          'Movies/家庭/生日🎂.mp4',
        ],
      );
      expect(
        archive.findFile('DCIM/相机/旅行/夏天🌻.jpg')!.content,
        memoryBytes,
      );
      expect(archive.findFile('Documents/报告.txt')!.content, diskBytes);
      expect(
        archive.findFile('Movies/家庭/生日🎂.mp4')!.content,
        contentBytes,
      );
      expect(uriContent.lengthRequests, 1);
      expect(uriContent.streamRequests, 1);
    });

    test('sanitizes Windows names and resolves case-insensitive collisions',
        () async {
      final harness = await _DownloadHarness.startFiles({
        'reserved': _webFile(
          id: 'reserved',
          fileName: 'CON/Album<2026>/NUL.txt/photo. ',
          bytes: [1],
        ),
        'question': _webFile(
          id: 'question',
          fileName: 'Camera/a?.jpg',
          bytes: [2],
        ),
        'asterisk': _webFile(
          id: 'asterisk',
          fileName: 'camera/A*.jpg',
          bytes: [3],
        ),
      });
      addTearDown(harness.close);

      final archive = ZipDecoder().decodeBytes(
        await _readBody(await harness.downloadAll()),
        verify: true,
      );
      final names = archive.files.map((file) => file.name).toList();

      expect(names.first, '_CON/Album_2026_/_NUL.txt/photo__');
      expect(names[1], matches(r'^Camera/a_~[0-9a-f]{8}\.jpg$'));
      expect(names[2], matches(r'^camera/A_~[0-9a-f]{8}\.jpg$'));
      expect(names.map((name) => name.toLowerCase()).toSet(), hasLength(3));
      expect(archive.files[0].content, [1]);
      expect(archive.files[1].content, [2]);
      expect(archive.files[2].content, [3]);
    });

    test('requires an active session belonging to the request IP', () async {
      final harness = await _DownloadHarness.start(_webFile(bytes: [1, 2]));
      addTearDown(harness.close);

      final missingResponse = await harness.downloadAll(sessionId: null);
      expect(missingResponse.statusCode, HttpStatus.badRequest);
      expect(await _readBody(missingResponse), isNotEmpty);

      final invalidResponse = await harness.downloadAll(sessionId: 'wrong');
      expect(invalidResponse.statusCode, HttpStatus.forbidden);
      expect(await _readBody(invalidResponse), isNotEmpty);

      final wrongIpHarness = await _DownloadHarness.start(
        _webFile(bytes: [1, 2]),
        sessionIp: '192.0.2.50',
      );
      addTearDown(wrongIpHarness.close);
      final wrongIpResponse = await wrongIpHarness.downloadAll();
      expect(wrongIpResponse.statusCode, HttpStatus.forbidden);
      expect(await _readBody(wrongIpResponse), isNotEmpty);
    });

    test('clearly rejects an unknown content URI size before streaming',
        () async {
      final uriContent = _FakeUriContent(
        length: null,
        chunks: const [
          [1, 2, 3],
        ],
      );
      final harness = await _DownloadHarness.start(
        _webFile(
          path: 'content://media/external/file/unknown',
          reportedSize: -1,
        ),
        uriContent: uriContent,
      );
      addTearDown(harness.close);

      final response = await harness.downloadAll();
      final body = String.fromCharCodes(await _readBody(response));

      expect(response.statusCode, 422);
      expect(response.headers.contentType?.mimeType, 'application/json');
      expect(body, contains('size is unknown'));
      expect(uriContent.lengthRequests, 1);
      expect(uriContent.streamRequests, 0);
    });
  });
}

WebSendFile _webFile({
  String id = 'file-id',
  String fileName = 'test.bin',
  List<int>? bytes,
  String? path,
  int? reportedSize,
}) {
  return WebSendFile(
    file: FileDto(
      id: id,
      fileName: fileName,
      size: reportedSize ?? bytes?.length ?? 0,
      fileType: FileType.other,
      hash: null,
      preview: null,
      metadata: null,
      legacy: false,
    ),
    asset: null,
    path: path,
    bytes: bytes,
  );
}

Future<List<int>> _readBody(HttpClientResponse response) {
  return response.fold<List<int>>(
    <int>[],
    (body, chunk) => body..addAll(chunk),
  );
}

class _DownloadHarness {
  _DownloadHarness._({
    required this.httpServer,
    required this.simpleServer,
    required this.client,
  });

  static const _sessionId = 'session-id';
  static const _fileId = 'file-id';

  final HttpServer httpServer;
  final SimpleServer simpleServer;
  final HttpClient client;

  static Future<_DownloadHarness> start(
    WebSendFile file, {
    UriContent? uriContent,
    String sessionIp = '127.0.0.1',
  }) =>
      startFiles(
        {_fileId: file},
        uriContent: uriContent,
        sessionIp: sessionIp,
      );

  static Future<_DownloadHarness> startFiles(
    Map<String, WebSendFile> files, {
    UriContent? uriContent,
    String sessionIp = '127.0.0.1',
  }) async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final routes = SimpleServerRouteBuilder();
    late ServerState state;
    late SimpleServer simpleServer;
    final serverUtils = ServerUtils(
      refFunc: () => throw UnsupportedError('Provider ref is not used.'),
      getState: () => state,
      getStateOrNull: () => state,
      setState: (builder) => state = builder(state)!,
    );
    SendController(
      serverUtils,
      uriContent: uriContent ?? _FakeUriContent(length: null, chunks: const []),
    ).installRoutes(
      router: routes,
      alias: 'LocalShare test',
      fingerprint: 'test-fingerprint',
    );
    simpleServer = SimpleServer.start(server: httpServer, routes: routes);
    state = ServerState(
      httpServer: simpleServer,
      alias: 'LocalShare test',
      port: httpServer.port,
      https: false,
      session: null,
      webSendState: WebSendState(
        sessions: {
          _sessionId: WebSendSession(
            sessionId: _sessionId,
            responseHandler: null,
            ip: sessionIp,
            deviceInfo: 'Test browser',
          ),
        },
        files: files,
        autoAccept: false,
        pin: null,
        pinAttempts: const {},
      ),
      pinAttempts: const {},
    );

    return _DownloadHarness._(
      httpServer: httpServer,
      simpleServer: simpleServer,
      client: HttpClient(),
    );
  }

  Future<HttpClientResponse> download({String? range}) async {
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: httpServer.address.address,
        port: httpServer.port,
        path: ApiRoute.download.v2,
        queryParameters: const {
          'sessionId': _sessionId,
          'fileId': _fileId,
        },
      ),
    );
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    return request.close();
  }

  Future<HttpClientResponse> downloadAll({
    String? sessionId = _sessionId,
  }) async {
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: httpServer.address.address,
        port: httpServer.port,
        path: '/api/localsend/v2/download-all',
        queryParameters: {
          if (sessionId != null) 'sessionId': sessionId,
        },
      ),
    );
    return request.close();
  }

  Future<void> close() async {
    client.close(force: true);
    await simpleServer.close();
  }
}

class _FakeUriContent extends UriContent {
  _FakeUriContent({
    required this.length,
    required this.chunks,
  }) : super.internal(const []);

  final int? length;
  final List<List<int>> chunks;
  int lengthRequests = 0;
  int streamRequests = 0;

  @override
  Future<int?> getContentLength(
    Uri uri, {
    Map<String, Object> httpHeaders = const {},
  }) async {
    lengthRequests++;
    return length;
  }

  @override
  Stream<Uint8List> getContentStream(
    Uri uri, {
    int bufferSize = 5 * 1024 * 1024,
    Map<String, Object> httpHeaders = const {},
  }) {
    streamRequests++;
    return Stream.fromIterable(chunks.map(Uint8List.fromList));
  }
}
