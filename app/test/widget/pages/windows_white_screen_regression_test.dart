import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/pages/dashboard_page.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  group('Windows white-screen layout regressions', () {
    test('main navigation exposes only the four primary tasks', () {
      expect(
        HomeTab.values,
        const [
          HomeTab.send,
          HomeTab.receive,
          HomeTab.backup,
          HomeTab.settings,
        ],
      );
    });

    testWidgets('extended brand mark lays out inside a desktop navigation rail',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: 0,
                  extended: true,
                  minExtendedWidth: 226,
                  leading: const Padding(
                    padding: EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: LocalShareBrandMark(extended: true),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.send_rounded),
                      label: Text('Send'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.download_rounded),
                      label: Text('Receive'),
                    ),
                  ],
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );

      expect(find.text(LocalShareCopy.appName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard accepts the unbounded height from its sliver',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        RefenaScope(
          overrides: [
            receiveTabVmProvider.overrideWithBuilder((_) => _dashboardVm),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DashboardPage(
                onOpenNativeTransfer: _doNothing,
                onOpenWebTransfer: _doNothing,
                onOpenBackup: _doNothing,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(SliverToBoxAdapter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone backup stays visible on a narrow Android-sized screen',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var openedBackup = false;

      await tester.pumpWidget(
        RefenaScope(
          overrides: [
            receiveTabVmProvider.overrideWithBuilder((_) => _dashboardVm),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.35),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: DashboardPage(
                onOpenNativeTransfer: _doNothing,
                onOpenWebTransfer: _doNothing,
                onOpenBackup: () async {
                  openedBackup = true;
                },
              ),
            ),
          ),
        ),
      );

      final shortcut = find.byKey(const Key('dashboard-backup-shortcut'));
      expect(shortcut, findsOneWidget);
      expect(tester.getRect(shortcut).top, lessThan(700));
      await tester.tap(shortcut);
      await tester.pump();

      expect(openedBackup, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tab changes are safe before the page controller attaches',
        (tester) async {
      final controller = ReduxNotifier.test(redux: HomePageController());
      addTearDown(controller.state.controller.dispose);

      expect(controller.state.controller.hasClients, isFalse);
      final initialState = controller.state;

      expect(
        () => controller.dispatch(ChangeTabAction(HomeTab.send)),
        returnsNormally,
      );
      expect(controller.state, same(initialState));

      expect(
        () => controller.dispatch(ChangeTabAction(HomeTab.receive)),
        returnsNormally,
      );
      expect(controller.state.currentTab, HomeTab.receive);

      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

final _dashboardVm = ReceiveTabVm(
  aliasSettings: 'Test PC',
  quickSaveSettings: false,
  quickSaveFromFavoritesSettings: false,
  serverState: null,
  localIps: const ['192.168.1.20'],
  showAdvanced: false,
  showHistoryButton: false,
  toggleAdvanced: _doNothing,
  onSetQuickSave: (_, __) => _doNothing(),
  onSetQuickSaveFromFavorites: (_, __) => _doNothing(),
);

Future<void> _doNothing() async {}
