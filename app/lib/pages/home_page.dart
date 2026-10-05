import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/backup/backup_page.dart';
import 'package:localsend_app/pages/dashboard_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/pages/tasks_page.dart';
import 'package:localsend_app/pages/web_receive_page.dart';
import 'package:localsend_app/pages/web_send_page.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/localshare_design/localshare_page_background.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum HomeTab {
  home(Icons.home_rounded),
  tasks(Icons.list_alt_rounded),
  send(Icons.send_rounded),
  backup(Icons.sync_rounded),
  settings(Icons.tune_rounded);

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.home:
        return LocalShareCopy.home;
      case HomeTab.send:
        return LocalShareCopy.send;
      case HomeTab.backup:
        return LocalShareCopy.isChinese ? '同步' : 'Sync';
      case HomeTab.settings:
        return LocalShareCopy.settings;
      case HomeTab.tasks:
        return LocalShareCopy.isChinese ? '任务' : 'Tasks';
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  bool _dragAndDropIndicator = false;

  @override
  void initState() {
    super.initState();

    ensureRef((ref) async {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
      if (mounted && ref.read(homePageControllerProvider).currentTab == HomeTab.home) {
        unawaited(ref.global.dispatchAsync(StartSmartScan(forceLegacy: false)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);
    final activeTasks = context.watch(taskProvider).tasks.values.where((task) => !task.terminal && task.stage != TransferTaskStage.paused).length;

    Widget tabIcon(HomeTab tab) =>
        tab == HomeTab.tasks && activeTasks > 0 ? Badge(label: Text('$activeTasks'), child: Icon(tab.icon)) : Icon(tab.icon);

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        if (event.files.length == 1 && Directory(event.files.first.path).existsSync()) {
          // user dropped a directory
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(event.files.first.path));
        } else {
          // user dropped one or more files
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddFilesAction(
                files: event.files,
                converter: CrossFileConverters.convertXFile,
              ));
        }
        vm.changeTab(HomeTab.send);
      },
      child: ResponsiveBuilder(
        builder: (sizingInformation) {
          return Scaffold(
            body: Row(
              children: [
                if (!sizingInformation.isMobile)
                  NavigationRail(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                    extended: sizingInformation.isDesktop,
                    minExtendedWidth: 226,
                    groupAlignment: -0.78,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    leading: Padding(
                      padding: EdgeInsets.fromLTRB(sizingInformation.isDesktop ? 18 : 10, 18, sizingInformation.isDesktop ? 18 : 10, 24),
                      child: LocalShareBrandMark(
                        extended: sizingInformation.isDesktop,
                      ),
                    ),
                    destinations: HomeTab.values.map((tab) {
                      return NavigationRailDestination(
                        icon: tabIcon(tab),
                        selectedIcon: tabIcon(tab),
                        label: Text(tab.label),
                      );
                    }).toList(),
                  ),
                Expanded(
                  child: SafeArea(
                    left: sizingInformation.isMobile,
                    child: LocalSharePageBackground(
                      child: Stack(
                        children: [
                          PageView(
                            controller: vm.controller,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              DashboardPage(
                                embedded: true,
                                onOpenNativeTransfer: () async => vm.changeTab(HomeTab.send),
                                onOpenWebTransfer: _openWebSend,
                                onOpenWebReceive: () async {
                                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WebReceivePage()));
                                },
                                onOpenBackup: () async => vm.changeTab(HomeTab.backup),
                                onOpenTasks: () async => vm.changeTab(HomeTab.tasks),
                                onOpenSettings: () async => vm.changeTab(HomeTab.settings),
                                onRefreshDevices: () async {
                                  await ref.global.dispatchAsync(StartSmartScan(forceLegacy: true));
                                },
                              ),
                              const TasksPage(),
                              const SendTab(),
                              BackupPage(
                                embedded: true,
                                onOpenNativeTransfer: () async => vm.changeTab(HomeTab.send),
                                onOpenReceive: () async => vm.changeTab(HomeTab.tasks),
                              ),
                              const SettingsTab(),
                            ],
                          ),
                          if (_dragAndDropIndicator)
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(context).scaffoldBackgroundColor,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.file_download, size: 128),
                                  const SizedBox(height: 30),
                                  Text(LocalShareCopy.dropToSend, style: Theme.of(context).textTheme.titleLarge),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: sizingInformation.isMobile
                ? NavigationBar(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                    destinations: HomeTab.values.map((tab) {
                      return NavigationDestination(icon: tabIcon(tab), label: tab.label);
                    }).toList(),
                  )
                : null,
          );
        },
      ),
    );
  }

  Future<void> _openWebSend() async {
    if (ref.read(selectedSendingFilesProvider).isEmpty) {
      await ref.global.dispatchAsync(PickFileAction(option: FilePickerOption.file, context: context));
    }
    if (!mounted) return;
    final files = ref.read(selectedSendingFilesProvider);
    if (files.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WebSendPage(files)));
  }
}

class LocalShareBrandMark extends StatelessWidget {
  final bool extended;

  const LocalShareBrandMark({required this.extended, super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(Icons.near_me_rounded, color: scheme.onPrimary, size: 22),
    );

    if (!extended) {
      return mark;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        SizedBox(
          width: 136,
          child: Text(
            LocalShareCopy.appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
        ),
      ],
    );
  }
}
