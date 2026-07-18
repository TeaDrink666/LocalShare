import 'package:common/isolate.dart';
import 'package:common/model/device.dart';
import 'package:common/model/file_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  group('SendTab simplified flow', () {
    testWidgets('only asks for content before a selection exists',
        (tester) async {
      await _pumpSendTab(
        tester,
        size: const Size(320, 700),
        textScaler: const TextScaler.linear(1.35),
        selectedFiles: const [],
      );

      expect(find.text('选择要发送的内容'), findsOneWidget);
      expect(find.text('附近设备'), findsNothing);
      expect(find.text('通过链接发送'), findsNothing);
      expect(tester.takeException(), isNull);
      await _disposeSendTab(tester);
    });

    testWidgets('keeps nearby devices above link sending on a narrow screen',
        (tester) async {
      var linkPageOpenCount = 0;
      await _pumpSendTab(
        tester,
        size: const Size(320, 700),
        textScaler: const TextScaler.linear(1.35),
        selectedFiles: const [_selectedFile],
        onSendMode: (context, mode) async {
          if (mode != SendMode.link) {
            return;
          }
          linkPageOpenCount++;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(child: Text('链接发送页')),
              ),
            ),
          );
        },
      );

      final nearby = find.text('附近设备');
      final link = find.text('通过链接发送');
      expect(nearby, findsOneWidget);
      expect(link, findsOneWidget);
      expect(
        tester.getTopLeft(link).dy,
        greaterThan(tester.getTopLeft(nearby).dy),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('链接发送页'), findsOneWidget);
      expect(linkPageOpenCount, 1);

      Navigator.of(tester.element(find.text('链接发送页'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('链接发送页'), findsOneWidget);
      expect(linkPageOpenCount, 2);

      Navigator.of(tester.element(find.text('链接发送页'))).pop();
      await tester.pumpAndSettle();
      await _disposeSendTab(tester);
    });

    testWidgets('uses two compact device columns on a wide screen',
        (tester) async {
      await _pumpSendTab(
        tester,
        size: const Size(1200, 800),
        textScaler: TextScaler.noScaling,
        selectedFiles: const [_selectedFile],
        devices: const [_phone, _desktop],
      );

      final phoneTop = tester.getTopLeft(find.text(_phoneName));
      final desktopTop = tester.getTopLeft(find.text(_desktopName));
      expect((phoneTop.dy - desktopTop.dy).abs(), lessThan(2));
      expect(desktopTop.dx, greaterThan(phoneTop.dx));
      expect(tester.takeException(), isNull);
      await _disposeSendTab(tester);
    });
  });
}

Future<void> _pumpSendTab(
  WidgetTester tester, {
  required Size size,
  required TextScaler textScaler,
  required List<CrossFile> selectedFiles,
  List<Device> devices = const [_phone],
  Future<void> Function(BuildContext, SendMode)? onSendMode,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final vm = SendTabVm(
    sendMode: SendMode.single,
    selectedFiles: selectedFiles,
    localIps: const ['192.168.1.20'],
    nearbyDevices: devices,
    favoriteDevices: const [],
    onTapAddress: _doNothingWithContext,
    onTapFavorite: _doNothingWithContext,
    onTapSendMode: onSendMode ?? _doNothingWithMode,
    onToggleFavorite: _doNothingWithDevice,
    onTapDevice: _doNothingWithDevice,
    onTapDeviceMultiSend: _doNothingWithDevice,
  );

  await tester.pumpWidget(
    RefenaScope(
      overrides: [
        sendTabVmProvider.overrideWithBuilder((_) => vm),
        animationProvider.overrideWithBuilder((_) => false),
        nearbyDevicesProvider.overrideWithNotifier(
          (_) => _TestNearbyDevicesService(devices),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const Scaffold(body: SendTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeSendTab(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 40));
}

class _TestNearbyDevicesService extends NearbyDevicesService {
  _TestNearbyDevicesService(List<Device> devices)
      : _devices = devices,
        super(
          isolateController: _MockIsolateController(),
          favoriteService: _MockFavoritesService(),
          discoveryLogs: _MockDiscoveryLogger(),
        );

  final List<Device> _devices;

  @override
  NearbyDevicesState init() => NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: const {},
        devices: {for (final device in _devices) device.ip: device},
      );
}

class _MockIsolateController extends Mock implements IsolateController {}

class _MockFavoritesService extends Mock implements FavoritesService {}

class _MockDiscoveryLogger extends Mock implements DiscoveryLogger {}

Future<void> _doNothingWithContext(BuildContext _) async {}

Future<void> _doNothingWithMode(BuildContext _, SendMode __) async {}

Future<void> _doNothingWithDevice(BuildContext _, Device __) async {}

const _selectedFile = CrossFile(
  name: 'photo.jpg',
  fileType: FileType.image,
  size: 2048,
  thumbnail: null,
  asset: null,
  path: r'C:\Pictures\photo.jpg',
  bytes: null,
  lastModified: null,
  lastAccessed: null,
);

const _phoneName = 'Alice Phone';
const _desktopName = 'Studio PC';

const _phone = Device(
  ip: '192.168.1.42',
  version: '1.17.0',
  port: 53317,
  https: false,
  fingerprint: 'alice-phone',
  alias: _phoneName,
  deviceModel: 'Android',
  deviceType: DeviceType.mobile,
  download: true,
);

const _desktop = Device(
  ip: '192.168.1.43',
  version: '1.17.0',
  port: 53317,
  https: false,
  fingerprint: 'studio-pc',
  alias: _desktopName,
  deviceModel: 'Windows',
  deviceType: DeviceType.desktop,
  download: true,
);
