import 'package:common/model/device.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/pages/receive_page_controller.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/selection/selected_receiving_files_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

const _senderName = 'Alice Pixel';
const _fileCount = 2;

void main() {
  group('ReceivePage request layout', () {
    testWidgets('lays out a file request at 320dp with enlarged text',
        (tester) async {
      await _pumpRequest(
        tester,
        size: const Size(320, 700),
        textScaler: const TextScaler.linear(1.35),
      );

      _expectRequestContent();

      await tester.ensureVisible(find.text(t.general.accept));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _disposeRequest(tester);
    });

    testWidgets('lays out a file request on a wide Windows-sized surface',
        (tester) async {
      await _pumpRequest(
        tester,
        size: const Size(1200, 800),
        textScaler: TextScaler.noScaling,
      );

      _expectRequestContent();
      expect(tester.takeException(), isNull);
      await _disposeRequest(tester);
    });
  });
}

Future<void> _pumpRequest(
  WidgetTester tester, {
  required Size size,
  required TextScaler textScaler,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final persistence = MockPersistenceService();
  when(persistence.getFavorites()).thenReturn(const []);

  await tester.pumpWidget(
    RefenaScope(
      overrides: [
        persistenceProvider.overrideWithValue(persistence),
        selectedReceivingFilesProvider.overrideWithNotifier(
          (_) => _SelectedFilesNotifier(),
        ),
        receivePageControllerProvider.overrideWithNotifier(
          (_) => _ReceiveRequestController(),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const ReceivePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectRequestContent() {
  expect(find.text(_senderName), findsOneWidget);
  expect(find.text(t.receivePage.subTitle(n: _fileCount)), findsOneWidget);
  expect(find.text(t.receiveOptionsPage.title), findsOneWidget);
  expect(find.text(t.general.decline), findsOneWidget);
  expect(find.text(t.general.accept), findsOneWidget);
}

Future<void> _disposeRequest(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 40));
}

class _ReceiveRequestController extends ReceivePageController {
  _ReceiveRequestController()
      : super(
          server: ServerService(),
          selectedReceivingFiles: _SelectedFilesNotifier(),
        );

  @override
  ReceivePageVm init() {
    return ReceivePageVm(
      status: SessionStatus.waiting,
      sender: const Device(
        ip: '192.168.1.42',
        version: '1.17.0',
        port: 53317,
        https: false,
        fingerprint: 'alice-phone',
        alias: _senderName,
        deviceModel: 'Pixel 9 Pro',
        deviceType: DeviceType.mobile,
        download: true,
      ),
      showSenderInfo: true,
      fileCount: _fileCount,
      message: null,
      isLink: false,
      showFullIp: false,
      onAccept: _doNothing,
      onDecline: _doNothing,
      onClose: _doNothing,
    );
  }

  @override
  get initialAction => null;
}

class _SelectedFilesNotifier extends SelectedReceivingFilesNotifier {
  @override
  Map<String, String> init() => const {
        'photo-id': 'photo.jpg',
        'video-id': 'video.mp4',
      };
}

void _doNothing() {}
