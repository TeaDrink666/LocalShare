import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/backup/backup_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/localshare_design/localshare_page_background.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum HomeTab {
  send(Icons.send_rounded),
  receive(Icons.download_rounded),
  backup(Icons.backup_rounded),
  settings(Icons.tune_rounded);

  const HomeTab(this.icon);

  final IconData icon;

  /// 兼容仍把旧首页作为启动目标的入口；新界面不会展示首页标签。
  @Deprecated('首页已移除，请使用 HomeTab.send')
  static const HomeTab home = HomeTab.send;

  String get label {
    switch (this) {
      case HomeTab.send:
        return LocalShareCopy.send;
      case HomeTab.receive:
        return LocalShareCopy.receive;
      case HomeTab.backup:
        return LocalShareCopy.backup;
      case HomeTab.settings:
        return LocalShareCopy.settings;
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
      ref
          .redux(homePageControllerProvider)
          .dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);

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
        if (event.files.length == 1 &&
            Directory(event.files.first.path).existsSync()) {
          // user dropped a directory
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(AddDirectoryAction(event.files.first.path));
        } else {
          // user dropped one or more files
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(AddFilesAction(
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
                    onDestinationSelected: (index) =>
                        vm.changeTab(HomeTab.values[index]),
                    extended: sizingInformation.isDesktop,
                    minExtendedWidth: 226,
                    groupAlignment: -0.78,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    leading: Padding(
                      padding: EdgeInsets.fromLTRB(
                          sizingInformation.isDesktop ? 18 : 10,
                          18,
                          sizingInformation.isDesktop ? 18 : 10,
                          24),
                      child: LocalShareBrandMark(
                        extended: sizingInformation.isDesktop,
                      ),
                    ),
                    destinations: HomeTab.values.map((tab) {
                      return NavigationRailDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.icon, fill: 1),
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
                              const SendTab(),
                              const ReceiveTab(),
                              BackupPage(
                                embedded: true,
                                onOpenNativeTransfer: () async =>
                                    vm.changeTab(HomeTab.send),
                                onOpenReceive: () async =>
                                    vm.changeTab(HomeTab.receive),
                              ),
                              const SettingsTab(),
                            ],
                          ),
                          if (_dragAndDropIndicator)
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.file_download, size: 128),
                                  const SizedBox(height: 30),
                                  Text(LocalShareCopy.dropToSend,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
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
                    onDestinationSelected: (index) =>
                        vm.changeTab(HomeTab.values[index]),
                    destinations: HomeTab.values.map((tab) {
                      return NavigationDestination(
                          icon: Icon(tab.icon), label: tab.label);
                    }).toList(),
                  )
                : null,
          );
        },
      ),
    );
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
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
        ),
      ],
    );
  }
}
