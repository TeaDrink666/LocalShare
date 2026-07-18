import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

const _deviceName = 'Studio PC';
const _destination = r'D:\LocalShare\Received';

void main() {
  group('ReceiveTab responsive layout', () {
    testWidgets('lays out on a narrow screen with enlarged text',
        (tester) async {
      await _pumpReceiveTab(
        tester,
        size: const Size(320, 700),
        textScaler: const TextScaler.linear(1.35),
      );

      _expectCoreRegions();

      final quickSaveTop = tester.getTopLeft(find.text(t.general.quickSave));
      final destinationTop =
          tester.getTopLeft(find.text(t.settingsTab.receive.destination));
      final webReceiveTop =
          tester.getTopLeft(find.text(LocalShareCopy.webReceiveTitle));
      expect(destinationTop.dy, lessThan(quickSaveTop.dy));
      expect(webReceiveTop.dy, greaterThan(quickSaveTop.dy));

      await tester.ensureVisible(find.text(_destination));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _disposeReceiveTab(tester);
    });

    testWidgets('uses two simple columns on a wide screen', (tester) async {
      await _pumpReceiveTab(
        tester,
        size: const Size(1200, 800),
        textScaler: TextScaler.noScaling,
      );

      _expectCoreRegions();

      final destinationTop =
          tester.getTopLeft(find.text(t.settingsTab.receive.destination));
      final webReceiveTop =
          tester.getTopLeft(find.text(LocalShareCopy.webReceiveTitle));
      expect(webReceiveTop.dx, greaterThan(destinationTop.dx));
      expect((destinationTop.dy - webReceiveTop.dy).abs(), lessThan(20));
      expect(tester.takeException(), isNull);
      await _disposeReceiveTab(tester);
    });

    testWidgets('shows network values only when details are expanded',
        (tester) async {
      await _pumpReceiveTab(
        tester,
        size: const Size(390, 800),
        textScaler: TextScaler.noScaling,
        showAdvanced: true,
      );

      expect(find.text(t.receiveTab.infoBox.ip), findsOneWidget);
      expect(find.text('192.168.1.42'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeReceiveTab(tester);
    });
  });
}

Future<void> _pumpReceiveTab(
  WidgetTester tester, {
  required Size size,
  required TextScaler textScaler,
  bool showAdvanced = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final persistence = MockPersistenceService();
  when(persistence.getDestination()).thenReturn(_destination);
  when(persistence.getEnableAnimations()).thenReturn(false);

  await tester.pumpWidget(
    RefenaScope(
      overrides: [
        receiveTabVmProvider.overrideWithBuilder(
          (_) => _receiveVm(showAdvanced: showAdvanced),
        ),
        settingsProvider
            .overrideWithNotifier((_) => SettingsService(persistence)),
        animationProvider.overrideWithBuilder((_) => false),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const Scaffold(body: ReceiveTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposeReceiveTab(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 40));
}

void _expectCoreRegions() {
  expect(find.text(_deviceName), findsOneWidget);
  expect(find.text(t.general.quickSave), findsOneWidget);
  expect(find.text(t.settingsTab.receive.destination), findsOneWidget);
  expect(find.text(_destination), findsOneWidget);
  expect(find.text(LocalShareCopy.webReceiveTitle), findsOneWidget);
  expect(find.byKey(const ValueKey('web-receive-button')), findsOneWidget);
  expect(find.byKey(const ValueKey('info-btn')), findsOneWidget);
}

ReceiveTabVm _receiveVm({required bool showAdvanced}) => ReceiveTabVm(
      aliasSettings: _deviceName,
      quickSaveSettings: false,
      quickSaveFromFavoritesSettings: false,
      serverState: null,
      localIps: const ['192.168.1.42'],
      showAdvanced: showAdvanced,
      showHistoryButton: true,
      toggleAdvanced: _doNothing,
      onSetQuickSave: (_, __) async {},
      onSetQuickSaveFromFavorites: (_, __) async {},
    );

Future<void> _doNothing() async {}
