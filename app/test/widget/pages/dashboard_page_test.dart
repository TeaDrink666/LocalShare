import 'package:common/model/device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/pages/dashboard_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/pages/tasks_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/widget/receive_mode_menu.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

void main() {
  testWidgets('home accepts and declines independent incoming requests', (tester) async {
    final container = _container();
    final service = container.notifier(taskProvider);
    service.put(_task('incoming-a', TransferTaskStage.waiting));
    service.put(_task('incoming-b', TransferTaskStage.waiting));
    var accepted = 0;
    var declined = 0;
    service.acceptances['incoming-a'] = () {
      accepted++;
      service.update('incoming-a', TransferTaskStage.running);
    };
    service.declines['incoming-b'] = () {
      declined++;
      service.update('incoming-b', TransferTaskStage.canceled);
    };
    await _pump(tester, container, size: const Size(1200, 900));
    await tester.tap(find.byKey(const ValueKey('accept-incoming-a')));
    await tester.pump();
    expect(accepted, 1);
    expect(service.state.tasks['incoming-a']!.stage, TransferTaskStage.running);
    expect(find.byKey(const ValueKey('dashboard-task-incoming-a')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('decline-incoming-b')));
    await tester.pump();
    expect(declined, 1);
    expect(service.state.tasks['incoming-b']!.stage, TransferTaskStage.canceled);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('web sending and receiving invoke distinct actions', (tester) async {
    var sent = false;
    var received = false;
    await _pump(tester, _container(), size: const Size(360, 800), onSendWeb: () async {
      sent = true;
    }, onReceiveWeb: () async {
      received = true;
    });
    await tester.tap(find.byKey(const Key('dashboard-web-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-web-send')));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
    expect(received, isFalse);
    await tester.tap(find.byKey(const Key('dashboard-web-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-web-receive')));
    await tester.pumpAndSettle();
    expect(received, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home progress includes checkpoints and detail back keeps task running', (tester) async {
    final container = _container();
    final service = container.notifier(taskProvider);
    service.put(_task('running', TransferTaskStage.running));
    container.notifier(progressProvider).setProgress(sessionId: 'running', fileId: 'file', progress: 0.1);
    var canceled = false;
    service.cancellations['running'] = () {
      canceled = true;
    };
    await _pump(tester, container, size: const Size(1200, 900));
    // Stored 40-byte checkpoint is retained even before live progress catches up.
    expect(find.textContaining('40.0%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dashboard-task-running')));
    await tester.pumpAndSettle();
    expect(find.byType(TasksPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(canceled, isFalse);
    expect(service.state.tasks['running']!.stage, TransferTaskStage.running);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320-pixel home supports large text and real nearby device refresh', (tester) async {
    var refreshed = false;
    var openedSend = false;
    final devices = NearbyDevicesState(runningFavoriteScan: false, runningIps: const {}, devices: const {
      '192.168.1.2': Device(
          ip: '192.168.1.2',
          version: '1',
          port: 53317,
          https: true,
          fingerprint: 'device',
          alias: 'My laptop with a long name',
          deviceModel: 'Windows',
          deviceType: DeviceType.desktop,
          download: true),
    });
    await _pump(tester, _container(devices: devices), size: const Size(320, 700), textScale: 1.5, onRefresh: () async {
      refreshed = true;
    }, onSend: () async {
      openedSend = true;
    });
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('dashboard-refresh-devices')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-refresh-devices')));
    await tester.pump();
    expect(refreshed, isTrue);
    await tester.ensureVisible(find.text('My laptop with a long name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My laptop with a long name'));
    await tester.pump();
    expect(openedSend, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('receiving modes disable the previous automatic mode first', (tester) async {
    final changes = <String>[];
    final vm = _vm(
        quickSave: true,
        onQuick: (_, enabled) async {
          changes.add('all:$enabled');
        },
        onFavorite: (_, enabled) async {
          changes.add('favorites:$enabled');
        });
    await tester.pumpWidget(RefenaScope(
        overrides: [receiveTabVmProvider.overrideWithBuilder((_) => vm)], child: const MaterialApp(home: Scaffold(body: ReceiveModeMenu()))));
    await tester.tap(find.byKey(const Key('receive-mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem<ReceiveMode> && widget.value == ReceiveMode.favorites));
    await tester.pumpAndSettle();
    expect(changes, ['all:false', 'favorites:true']);
    await tester.pumpWidget(const SizedBox());
  });
}

RefenaContainer _container({NearbyDevicesState devices = const NearbyDevicesState(runningFavoriteScan: false, runningIps: {}, devices: {})}) {
  final persistence = MockPersistenceService();
  when(persistence.getTaskConcurrency()).thenReturn(2);
  return RefenaContainer(overrides: [
    persistenceProvider.overrideWithValue(persistence),
    receiveTabVmProvider.overrideWithBuilder((_) => _vm()),
    dashboardDevicesProvider.overrideWithBuilder((_) => devices),
  ]);
}

Future<void> _pump(
  WidgetTester tester,
  RefenaContainer container, {
  required Size size,
  double textScale = 1,
  Future<void> Function()? onSendWeb,
  Future<void> Function()? onReceiveWeb,
  Future<void> Function()? onRefresh,
  Future<void> Function()? onSend,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(RefenaScope.withContainer(
      container: container,
      child: MaterialApp(
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
          home: Scaffold(
              body: DashboardPage(
                  embedded: true,
                  onOpenNativeTransfer: onSend ?? _noop,
                  onOpenWebTransfer: onSendWeb ?? _noop,
                  onOpenWebReceive: onReceiveWeb ?? _noop,
                  onOpenBackup: _noop,
                  onOpenTasks: _noop,
                  onOpenSettings: _noop,
                  onRefreshDevices: onRefresh ?? _noop)))));
}

TransferTask _task(String id, TransferTaskStage stage) => TransferTask(
        id: id,
        kind: TransferTaskKind.receive,
        peer: 'Phone',
        stage: stage,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        startedAt: DateTime.now().millisecondsSinceEpoch - 10000,
        files: const [
          {'id': 'file', 'name': 'project/main.dart', 'size': 100, 'status': 'sending', 'receivedBytes': 40}
        ]);

ReceiveTabVm _vm({
  bool quickSave = false,
  Future<void> Function(BuildContext, bool)? onQuick,
  Future<void> Function(BuildContext, bool)? onFavorite,
}) =>
    ReceiveTabVm(
        aliasSettings: 'My PC',
        quickSaveSettings: quickSave,
        quickSaveFromFavoritesSettings: false,
        serverState: null,
        localIps: const ['192.168.1.1'],
        showAdvanced: false,
        showHistoryButton: false,
        toggleAdvanced: _noop,
        onSetQuickSave: onQuick ?? (_, __) async {},
        onSetQuickSaveFromFavorites: onFavorite ?? (_, __) async {});

Future<void> _noop() async {}
