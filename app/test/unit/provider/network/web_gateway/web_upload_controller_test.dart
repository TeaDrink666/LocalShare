import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common/model/device.dart';
import 'package:common/model/device_info_result.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/dto/info_register_dto.dart';
import 'package:common/model/dto/prepare_upload_request_dto.dart';
import 'package:common/model/dto/prepare_upload_response_dto.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/session_status.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:localsend_app/model/state/web_gateway/web_gateway_state.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/web_gateway/controller/web_upload_controller.dart';
import 'package:localsend_app/provider/network/web_gateway/web_gateway_utils.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/simple_server.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  group('web upload routes', () {
    test('concurrent identical relative paths preserve names in separate task folders', () async {
      final harness = await _UploadHarness.start();
      addTearDown(harness.close);
      final first = harness.prepare(name: 'project/lib/main.dart', taskId: 'first');
      await _pumpUntil(() => harness.state.receiveSessions.length == 1);
      final firstId = harness.state.receiveSessions.keys.single;
      harness.container.notifier(taskProvider).accept(firstId);
      final a = await _body(await first);
      final second = harness.prepare(name: 'project/lib/main.dart', taskId: 'second');
      await _pumpUntil(() => harness.state.receiveSessions.length == 2);
      final secondId = harness.state.receiveSessions.keys.firstWhere((id) => id != firstId);
      harness.container.notifier(taskProvider).accept(secondId);
      final b = await _body(await second);
      for (final body in [a, b]) {
        expect((await harness.admit(body)).statusCode, 200);
      }
      final responses = await Future.wait([
        harness.upload(sessionId: a['sessionId'] as String, token: (a['files'] as Map)['file-1'] as String, bytes: 'first'.codeUnits),
        harness.upload(sessionId: b['sessionId'] as String, token: (b['files'] as Map)['file-1'] as String, bytes: 'other'.codeUnits),
      ]);
      expect(responses.map((r) => r.statusCode), [200, 200]);
      final paths = harness.state.receiveSessions.values.map((s) => '${s.destinationDirectory}/project/lib/main.dart').toList();
      expect(paths[0], isNot(paths[1]));
      expect(await File(paths[0]).readAsString(), 'first');
      expect(await File(paths[1]).readAsString(), 'other');
    });

    test('third transfer queues and canceling one leaves the other independent', () async {
      final harness = await _UploadHarness.start();
      addTearDown(harness.close);
      final prepared = <Map<String, dynamic>>[];
      for (var i = 0; i < 3; i++) {
        final request = harness.prepare(taskId: 'queued-$i');
        await _pumpUntil(() => harness.state.receiveSessions.length == i + 1);
        final id = harness.state.receiveSessions.keys.last;
        harness.container.notifier(taskProvider).accept(id);
        prepared.add(await _body(await request));
      }
      expect(harness.container.notifier(taskProvider).queue.activeCount, 0);
      expect((await harness.admit(prepared[0])).statusCode, 200);
      expect((await harness.admit(prepared[1])).statusCode, 200);
      expect((await harness.admit(prepared[2])).statusCode, 409);
      expect((await harness.cancel(sessionId: prepared[0]['sessionId'] as String)).statusCode, 200);
      expect(harness.state.receiveSessions.containsKey(prepared[1]['sessionId']), isTrue);
      expect((await harness.admit(prepared[2])).statusCode, 200);
    });

    test('paused transfer resumes from durable bytes and acknowledges final file once', () async {
      final harness = await _UploadHarness.start();
      addTearDown(harness.close);
      final prepare = harness.prepare(taskId: 'resume');
      await _pumpUntil(() => harness.state.receiveSessions.isNotEmpty);
      harness.container.notifier(taskProvider).accept(harness.state.receiveSessions.keys.single);
      final initial = await _body(await prepare);
      await harness.admit(initial);
      final hash = sha256.convert('hello'.codeUnits).toString();
      final first = await harness.chunk(initial, hash: hash, offset: 0, bytes: 'he'.codeUnits);
      expect(first.statusCode, 200);
      expect((await _body(first))['offset'], 2);
      await harness.cancel(sessionId: initial['sessionId'] as String, paused: true);
      final retry = harness.prepare(taskId: 'resume');
      final resumed = await _body(await retry); // identical approved manifest is reused
      expect(resumed['sessionId'], initial['sessionId']);
      await harness.admit(resumed);
      final status = await harness.status(resumed, hash);
      expect((await _body(status))['offset'], 2);
      expect((await harness.chunk(resumed, hash: hash, offset: 2, bytes: 'llo'.codeUnits)).statusCode, 200);
      expect((await _body(await harness.status(resumed, hash)))['committed'], isTrue);
      final session = harness.state.receiveSessions[resumed['sessionId']]!;
      expect(await File('${session.destinationDirectory}/hello.txt').readAsString(), 'hello');
      expect(harness.container.notifier(taskProvider).queue.activeCount, 0);
    });
    test('prepare, accept and upload save the file and finish the session', () async {
      final harness = await _UploadHarness.start();
      addTearDown(harness.close);

      final prepareFuture = harness.prepare();
      await _pumpUntil(() => harness.state.receiveSession != null);
      expect(harness.state.receiveSession!.status, SessionStatus.waiting);

      harness.controller.acceptRequest();
      final prepareResponse = await prepareFuture;
      expect(prepareResponse.statusCode, HttpStatus.ok);
      final prepareBody = jsonDecode(
        await prepareResponse.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      expect(prepareBody['sessionId'], harness.state.receiveSession!.sessionId);
      final token = (prepareBody['files'] as Map<String, dynamic>)['file-1'] as String;
      expect(token, isNotNull);

      final uploadResponse = await harness.upload(
        sessionId: prepareBody['sessionId'] as String,
        token: token,
        bytes: 'hello'.codeUnits,
      );
      expect(uploadResponse.statusCode, HttpStatus.ok);

      final saved = File(
        '${harness.state.receiveSession!.destinationDirectory}${Platform.pathSeparator}hello.txt',
      );
      expect(await saved.exists(), isTrue);
      expect(await saved.readAsBytes(), 'hello'.codeUnits);
      expect(
        harness.state.receiveSession!.files['file-1']!.status,
        FileStatus.finished,
      );
      expect(harness.state.receiveSession!.status, SessionStatus.finished);
    });

    test('declining the request returns 403 and clears the session', () async {
      final harness = await _UploadHarness.start();
      addTearDown(harness.close);

      final prepareFuture = harness.prepare();
      await _pumpUntil(() => harness.state.receiveSession != null);
      harness.controller.declineRequest();

      final prepareResponse = await prepareFuture;
      expect(prepareResponse.statusCode, HttpStatus.forbidden);
      expect(harness.state.receiveSession, isNull);
    });

    test('cancel clears a started upload session', () async {
      final harness = await _UploadHarness.start();
      addTearDown(harness.close);

      final prepareFuture = harness.prepare();
      await _pumpUntil(() => harness.state.receiveSession != null);
      harness.controller.acceptRequest();
      final prepareResponse = await prepareFuture;
      final sessionId = jsonDecode(
        await prepareResponse.transform(utf8.decoder).join(),
      )['sessionId'] as String;

      final cancelResponse = await harness.cancel(sessionId: sessionId);
      expect(cancelResponse.statusCode, HttpStatus.ok);
      expect(harness.state.receiveSession, isNull);
    });
  });
}

class _UploadHarness {
  _UploadHarness._({
    required this.holder,
    required this.port,
    required this.client,
    required this.controller,
    required this.tempDirectory,
    required this.container,
  });

  final _StateHolder holder;
  final int port;
  final HttpClient client;
  final WebUploadController controller;
  final Directory tempDirectory;
  final RefenaContainer container;

  WebGatewayState get state => holder.value;

  static Future<_UploadHarness> start() async {
    MapperContainer.globals.use(const FileDtoMapper());
    InfoRegisterDtoMapper.ensureInitialized();
    PrepareUploadRequestDtoMapper.ensureInitialized();
    PrepareUploadResponseDtoMapper.ensureInitialized();
    final tempDirectory = await Directory.systemTemp.createTemp(
      'localshare-web-upload-',
    );
    PathProviderPlatform.instance = _FakePathProvider(tempDirectory);
    final persistence = MockPersistenceService();
    when(persistence.getTaskConcurrency()).thenReturn(2);
    when(persistence.getDestination()).thenReturn(tempDirectory.path);
    when(persistence.isSaveToGallery()).thenReturn(false);
    when(persistence.getReceiveHistory()).thenReturn(const []);
    when(persistence.isSaveToHistory()).thenReturn(true);

    final container = RefenaContainer(
      overrides: [
        persistenceProvider.overrideWithValue(persistence),
        settingsProvider.overrideWithNotifier(
          (_) => SettingsService(persistence),
        ),
        deviceRawInfoProvider.overrideWithValue(
          DeviceInfoResult(
            deviceType: DeviceType.desktop,
            deviceModel: null,
            androidSdkInt: null,
          ),
        ),
        receiveHistoryProvider.overrideWithNotifier(
          (_) => ReceiveHistoryService(persistence),
        ),
      ],
    );

    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final routes = SimpleServerRouteBuilder();
    final simpleServer = SimpleServer.start(
      server: httpServer,
      routes: routes,
    );
    final holder = _StateHolder(
      WebGatewayState(
        httpServer: simpleServer,
        port: httpServer.port,
        webSendState: null,
        receiveSession: null,
        pinAttempts: const {},
        receivePinAttempts: const {},
      ),
    );
    final utils = WebGatewayUtils(
      refFunc: () => container,
      getState: () => holder.value,
      getStateOrNull: () => holder.value,
      setState: (builder) => holder.value = builder(holder.value)!,
    );
    final controller = WebUploadController(utils);
    controller.installRoutes(router: routes, port: httpServer.port);

    return _UploadHarness._(
      holder: holder,
      port: httpServer.port,
      client: HttpClient(),
      controller: controller,
      tempDirectory: tempDirectory,
      container: container,
    );
  }

  Future<HttpClientResponse> prepare({String name = 'hello.txt', String? taskId}) async {
    final request = await client.postUrl(
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/api/localsend/v2/prepare-upload',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      if (taskId != null) 'localshareTaskId': taskId,
      'info': {
        'alias': 'Browser',
        'version': '2.1',
        'deviceModel': 'Test browser',
        'deviceType': 'web',
        'fingerprint': 'browser-1',
        'port': 0,
        'protocol': 'http',
        'download': false,
      },
      'files': {
        'file-1': {
          'id': 'file-1',
          'fileName': name,
          'size': 5,
          'fileType': 'text/plain',
        },
      },
    }));
    return request.close();
  }

  Future<HttpClientResponse> upload({
    required String sessionId,
    required String token,
    required List<int> bytes,
  }) async {
    final request = await client.postUrl(
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/api/localsend/v2/upload',
        queryParameters: {
          'sessionId': sessionId,
          'fileId': 'file-1',
          'token': token,
        },
      ),
    );
    request.add(bytes);
    return request.close();
  }

  Future<HttpClientResponse> cancel({required String sessionId, bool paused = false}) async {
    final request = await client.postUrl(
      Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: '/api/localsend/v2/cancel',
        queryParameters: {'sessionId': sessionId, if (paused) 'ifPaused': '1'},
      ),
    );
    return request.close();
  }

  Future<HttpClientResponse> admit(Map<String, dynamic> prepared) => _extension(prepared, 'start');
  Future<HttpClientResponse> status(Map<String, dynamic> prepared, String hash) => _extension(prepared, 'status', hash: hash, get: true);
  Future<HttpClientResponse> chunk(Map<String, dynamic> prepared, {required String hash, required int offset, required List<int> bytes}) =>
      _extension(prepared, 'chunk', hash: hash, offset: offset, bytes: bytes);
  Future<HttpClientResponse> _extension(Map<String, dynamic> prepared, String route,
      {String? hash, int? offset, List<int>? bytes, bool get = false}) async {
    final uri = Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/api/localshare/v1/transfer/$route', queryParameters: {
      'sessionId': prepared['sessionId'] as String,
      'fileId': 'file-1',
      'token': (prepared['files'] as Map)['file-1'] as String,
      if (hash != null) 'sha256': hash,
      if (offset != null) 'offset': '$offset'
    });
    final request = get ? await client.getUrl(uri) : await client.postUrl(uri);
    if (bytes != null) {
      request.headers.set('x-localshare-chunk-sha256', sha256.convert(bytes).toString());
      request.add(bytes);
    }
    return request.close();
  }

  Future<void> close() async {
    client.close(force: true);
    await holder.value.httpServer.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  }
}

Future<Map<String, dynamic>> _body(HttpClientResponse response) async =>
    jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;

Future<void> _pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class _StateHolder {
  _StateHolder(this.value);

  WebGatewayState value;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getTemporaryPath() async => directory.path;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;

  @override
  Future<String?> getDownloadsPath() async => directory.path;
}
