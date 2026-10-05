import 'dart:io';

import 'package:common/isolate.dart';
import 'package:common/model/device.dart';
import 'package:common/model/device_info_result.dart';
import 'package:common/model/dto/multicast_dto.dart';
import 'package:common/model/file_type.dart';
import 'package:common/model/stored_security_context.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/network/web_gateway/web_gateway_provider.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../../../mocks.mocks.dart';

void main() {
  test('startWebSend uses a separate free port and initializes the session', () async {
    final nativePort = await _freePort();
    final container = _container(nativePort: nativePort);

    final service = container.notifier(webGatewayProvider);
    await service.startWebSend(
      files: [
        CrossFile(
          name: 'hello.txt',
          fileType: FileType.text,
          size: 5,
          thumbnail: null,
          asset: null,
          path: null,
          bytes: 'hello'.codeUnits,
          lastModified: null,
          lastAccessed: null,
        ),
      ],
    );

    final state = container.read(webGatewayProvider);
    expect(state, isNotNull);
    expect(state!.port, isNot(nativePort));
    expect(state.port, greaterThan(0));
    expect(state.webSendState, isNotNull);
    expect(state.webSendState!.files, hasLength(1));
    expect(
      state.webSendState!.files.values.single.file.fileName,
      'hello.txt',
    );

    await service.stop();
    expect(container.read(webGatewayProvider), isNull);
  });

  test('startWebSend falls back to an OS-assigned port when port + 1 is busy', () async {
    final nativePort = await _freePort();
    // Occupy the preferred candidate port.
    final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, nativePort + 1);
    addTearDown(blocker.close);
    final container = _container(nativePort: nativePort);

    final service = container.notifier(webGatewayProvider);
    await service.startWebSend(files: []);

    final state = container.read(webGatewayProvider);
    expect(state, isNotNull);
    expect(state!.port, isNot(nativePort));
    expect(state.port, isNot(nativePort + 1));
    expect(state.port, greaterThan(0));

    await service.stop();
    expect(container.read(webGatewayProvider), isNull);
  });

  test('repeated startWebSend replaces the previous session', () async {
    final nativePort = await _freePort();
    final container = _container(nativePort: nativePort);

    final service = container.notifier(webGatewayProvider);
    await service.startWebSend(
      files: [
        CrossFile(
          name: 'a.txt',
          fileType: FileType.text,
          size: 1,
          thumbnail: null,
          asset: null,
          path: null,
          bytes: 'a'.codeUnits,
          lastModified: null,
          lastAccessed: null,
        ),
      ],
    );
    final firstPort = container.read(webGatewayProvider)!.port;
    await service.startWebSend(
      files: [
        CrossFile(
          name: 'b.txt',
          fileType: FileType.text,
          size: 1,
          thumbnail: null,
          asset: null,
          path: null,
          bytes: 'b'.codeUnits,
          lastModified: null,
          lastAccessed: null,
        ),
      ],
    );
    final secondState = container.read(webGatewayProvider)!;
    expect(secondState.port, firstPort);
    expect(
      secondState.webSendState!.files.values.single.file.fileName,
      'b.txt',
    );

    await service.stop();
  });

  test('pin, autoAccept, accept and decline route to the web send state', () async {
    final nativePort = await _freePort();
    final container = _container(nativePort: nativePort);

    final service = container.notifier(webGatewayProvider);
    await service.startWebSend(files: []);

    service.setWebSendPin('1234');
    expect(
      container.read(webGatewayProvider)!.webSendState!.pin,
      '1234',
    );
    service.setWebSendAutoAccept(true);
    expect(
      container.read(webGatewayProvider)!.webSendState!.autoAccept,
      isTrue,
    );

    await service.stop();
    expect(container.read(webGatewayProvider), isNull);
  });

  test('startWebReceive opens the listener and stopWebReceive closes it', () async {
    final nativePort = await _freePort();
    final container = _container(nativePort: nativePort);

    final service = container.notifier(webGatewayProvider);
    await service.startWebReceive();
    final state = container.read(webGatewayProvider);
    expect(state, isNotNull);
    expect(state!.port, nativePort + 1);
    expect(state.webSendState, isNull);
    expect(state.receiveSession, isNull);

    await service.stopWebReceive();
    expect(container.read(webGatewayProvider), isNull);
  });

  test('web send and web receive share one listener and close it only when idle', () async {
    final nativePort = await _freePort();
    final container = _container(nativePort: nativePort);

    final service = container.notifier(webGatewayProvider);
    await service.startWebSend(files: const []);
    final sendPort = container.read(webGatewayProvider)!.port;

    // Opening web receive reuses the running listener.
    await service.startWebReceive();
    expect(container.read(webGatewayProvider)!.port, sendPort);

    // Closing web receive keeps the listener while web send is active.
    await service.stopWebReceive();
    expect(container.read(webGatewayProvider), isNotNull);

    // Closing web send when nothing else is active stops the listener.
    await service.stopWebSend();
    expect(container.read(webGatewayProvider), isNull);
  });
}

RefenaContainer _container({required int nativePort}) {
  final persistence = MockPersistenceService();
  when(persistence.getPort()).thenReturn(nativePort);
  when(persistence.getSecurityContext()).thenReturn(
    const StoredSecurityContext(
      privateKey: 'test-private-key',
      publicKey: 'test-public-key',
      certificate: 'test-certificate',
      certificateHash: 'test-fingerprint',
    ),
  );

  return RefenaContainer(
    overrides: [
      settingsProvider.overrideWithNotifier(
        (_) => SettingsService(persistence),
      ),
      securityProvider.overrideWithNotifier(
        (_) => SecurityService(persistence),
      ),
      parentIsolateProvider.overrideWithNotifier(
        (_) => IsolateController(
          initialState: ParentIsolateState.initial(
            SyncState(
              init: () async {},
              rootIsolateToken: Object(),
              httpClientFactory: (timeout, securityContext) {
                throw UnsupportedError('No HTTP client in unit tests.');
              },
              securityContext: const StoredSecurityContext(
                privateKey: 'test-private-key',
                publicKey: 'test-public-key',
                certificate: 'test-certificate',
                certificateHash: 'test-fingerprint',
              ),
              deviceInfo: DeviceInfoResult(
                deviceType: DeviceType.desktop,
                deviceModel: null,
                androidSdkInt: null,
              ),
              alias: 'LocalShare test',
              port: nativePort,
              networkWhitelist: null,
              networkBlacklist: null,
              protocol: ProtocolType.http,
              multicastGroup: '224.0.0.167',
              discoveryTimeout: 20,
              serverRunning: false,
              download: false,
            ),
          ),
        ),
      ),
    ],
  );
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
