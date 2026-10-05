import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/pages/web_receive_page.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const _pageMaxWidth = 1040.0;
const _wideLayoutBreakpoint = 760.0;

enum _QuickSaveMode {
  off,
  favorites,
  on,
}

class ReceiveTab extends StatelessWidget {
  const ReceiveTab({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(receiveTabVmProvider);
    final destination = context.watch(settingsProvider.select((settings) => settings.destination));

    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _pageMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _PageHeader(),
                      const SizedBox(height: 14),
                      _DeviceSummary(vm: vm),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final destinationSection = _DestinationSection(destination: destination);
                          final quickSaveSection = _QuickSaveSection(vm: vm);
                          final webReceiveSection = const _WebReceiveSection();
                          final networkDetails = _NetworkDetails(vm: vm);

                          if (constraints.maxWidth < _wideLayoutBreakpoint) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                destinationSection,
                                const SizedBox(height: 12),
                                quickSaveSection,
                                const SizedBox(height: 12),
                                webReceiveSection,
                                const SizedBox(height: 12),
                                networkDetails,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    destinationSection,
                                    const SizedBox(height: 12),
                                    quickSaveSection,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    webReceiveSection,
                                    const SizedBox(height: 12),
                                    networkDetails,
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            t.receiveTab.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
          ),
        ),
        TextButton.icon(
          key: const ValueKey('receive-history-button'),
          onPressed: () async {
            await context.push(() => const ReceiveHistoryPage());
          },
          icon: const Icon(Icons.history_rounded),
          label: Text(_ReceiveCopy.history),
        ),
      ],
    );
  }
}

class _DeviceSummary extends StatelessWidget {
  final ReceiveTabVm vm;

  const _DeviceSummary({required this.vm});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOnline = vm.serverState != null;
    final alias = vm.serverState?.alias ?? vm.aliasSettings;
    final statusColor = isOnline ? scheme.primary : scheme.onSurfaceVariant;

    return LocalShareCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isOnline ? Icons.devices_rounded : Icons.wifi_off_rounded,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alias,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? statusColor : statusColor.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        isOnline ? _ReceiveCopy.ready : t.general.offline,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationSection extends StatelessWidget {
  final String? destination;

  const _DestinationSection({required this.destination});

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      icon: Icons.folder_outlined,
      title: t.settingsTab.receive.destination,
      trailing: TextButton(
        onPressed: () {
          context.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.settings));
        },
        child: Text(t.general.edit),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DestinationPath(destination: destination),
          const SizedBox(height: 6),
          Text(
            destination == null ? _ReceiveCopy.defaultPathHint : _ReceiveCopy.customPathHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _DestinationPath extends StatefulWidget {
  final String? destination;

  const _DestinationPath({required this.destination});

  @override
  State<_DestinationPath> createState() => _DestinationPathState();
}

class _DestinationPathState extends State<_DestinationPath> {
  Future<String>? _defaultDestination;

  @override
  void initState() {
    super.initState();
    _refreshDefaultDestination();
  }

  @override
  void didUpdateWidget(covariant _DestinationPath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination) {
      _refreshDefaultDestination();
    }
  }

  void _refreshDefaultDestination() {
    if (widget.destination == null) {
      _defaultDestination = Future.sync(getDefaultDestinationDirectory);
    } else {
      _defaultDestination = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destination case final String destination) {
      return _buildPath(context, destination);
    }

    return FutureBuilder<String>(
      future: _defaultDestination,
      builder: (context, snapshot) {
        final label = switch (snapshot.connectionState) {
          ConnectionState.done when snapshot.hasData => snapshot.data!,
          ConnectionState.done => _ReceiveCopy.defaultDestinationUnavailable,
          _ => _ReceiveCopy.defaultDestinationResolving,
        };
        return _buildPath(context, label);
      },
    );
  }

  Widget _buildPath(BuildContext context, String path) {
    return SelectableText(
      path,
      maxLines: 4,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
    );
  }
}

class _QuickSaveSection extends StatelessWidget {
  final ReceiveTabVm vm;

  const _QuickSaveSection({required this.vm});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedMode = _selectedQuickSaveMode(vm);

    return _SectionFrame(
      icon: Icons.verified_user_outlined,
      title: t.general.quickSave,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ReceiveCopy.quickSaveSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickSaveChoice(
                label: t.receiveTab.quickSave.off,
                selected: selectedMode == _QuickSaveMode.off,
                onSelected: () async => _setQuickSaveMode(context, vm, _QuickSaveMode.off),
              ),
              _QuickSaveChoice(
                label: t.receiveTab.quickSave.favorites,
                selected: selectedMode == _QuickSaveMode.favorites,
                onSelected: () async => _setQuickSaveMode(context, vm, _QuickSaveMode.favorites),
              ),
              _QuickSaveChoice(
                label: t.receiveTab.quickSave.on,
                selected: selectedMode == _QuickSaveMode.on,
                onSelected: () async => _setQuickSaveMode(context, vm, _QuickSaveMode.on),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _quickSaveDescription(selectedMode),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _QuickSaveChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final Future<void> Function() onSelected;

  const _QuickSaveChoice({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      showCheckmark: true,
      label: Text(label),
      onSelected: (value) async {
        if (value) {
          await onSelected();
        }
      },
    );
  }
}

class _WebReceiveSection extends StatelessWidget {
  const _WebReceiveSection();

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      icon: Icons.language_rounded,
      title: LocalShareCopy.webReceiveTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            LocalShareCopy.webReceiveSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('web-receive-button'),
            onPressed: () async {
              await context.push(() => const WebReceivePage());
            },
            icon: const Icon(Icons.qr_code_rounded),
            label: Text(LocalShareCopy.openUploadPortal),
          ),
        ],
      ),
    );
  }
}

class _NetworkDetails extends StatelessWidget {
  final ReceiveTabVm vm;

  const _NetworkDetails({required this.vm});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LocalShareRadii.large),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('info-btn'),
              onTap: vm.toggleAdvanced,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.lan_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _ReceiveCopy.networkDetails,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: vm.showAdvanced ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: vm.showAdvanced
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: scheme.outlineVariant),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = 16.0;
                            final columns = constraints.maxWidth >= 600
                                ? 3
                                : constraints.maxWidth >= 360
                                    ? 2
                                    : 1;
                            final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

                            return Wrap(
                              spacing: gap,
                              runSpacing: 14,
                              children: [
                                _NetworkValue(
                                  width: itemWidth,
                                  label: t.receiveTab.infoBox.alias,
                                  value: vm.serverState?.alias ?? vm.aliasSettings,
                                ),
                                _NetworkValue(
                                  width: itemWidth,
                                  label: t.receiveTab.infoBox.ip,
                                  value: vm.localIps.isEmpty ? t.general.unknown : vm.localIps.join('\n'),
                                ),
                                _NetworkValue(
                                  width: itemWidth,
                                  label: t.receiveTab.infoBox.port,
                                  value: vm.serverState?.port.toString() ?? '-',
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _NetworkValue extends StatelessWidget {
  final double width;
  final String label;
  final String value;

  const _NetworkValue({
    required this.width,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionFrame({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LocalShareRadii.large),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

_QuickSaveMode _selectedQuickSaveMode(ReceiveTabVm vm) {
  if (vm.quickSaveSettings) {
    return _QuickSaveMode.on;
  }
  if (vm.quickSaveFromFavoritesSettings) {
    return _QuickSaveMode.favorites;
  }
  return _QuickSaveMode.off;
}

Future<void> _setQuickSaveMode(
  BuildContext context,
  ReceiveTabVm vm,
  _QuickSaveMode mode,
) async {
  switch (mode) {
    case _QuickSaveMode.off:
      await vm.onSetQuickSave(context, false);
      if (context.mounted) {
        await vm.onSetQuickSaveFromFavorites(context, false);
      }
    case _QuickSaveMode.favorites:
      await vm.onSetQuickSave(context, false);
      if (context.mounted) {
        await vm.onSetQuickSaveFromFavorites(context, true);
      }
    case _QuickSaveMode.on:
      await vm.onSetQuickSaveFromFavorites(context, false);
      if (context.mounted) {
        await vm.onSetQuickSave(context, true);
      }
  }
}

String _quickSaveDescription(_QuickSaveMode mode) {
  return switch (mode) {
    _QuickSaveMode.off => _ReceiveCopy.quickSaveOffDescription,
    _QuickSaveMode.favorites => _ReceiveCopy.quickSaveFavoritesDescription,
    _QuickSaveMode.on => _ReceiveCopy.quickSaveOnDescription,
  };
}

abstract final class _ReceiveCopy {
  static bool get _isChinese => switch (LocaleSettings.currentLocale) {
        AppLocale.zhCn || AppLocale.zhHk || AppLocale.zhTw => true,
        _ => false,
      };

  static String get history => _isChinese ? '历史' : 'History';
  static String get networkDetails => _isChinese ? '网络详情' : 'Network details';
  static String get ready => _isChinese ? '在线，可以接收文件' : 'Online and ready to receive';
  static String get quickSaveSubtitle => _isChinese ? '设置收到传输请求时是否需要确认。' : 'Choose whether incoming transfers need approval.';
  static String get quickSaveOffDescription => _isChinese ? '每次收到文件都先询问。' : 'Ask before saving every transfer.';
  static String get quickSaveFavoritesDescription => _isChinese ? '收藏设备自动接收，其他设备仍会询问。' : 'Auto-save from favorites and ask for all other devices.';
  static String get quickSaveOnDescription => _isChinese ? '所有设备自动接收，仅建议在可信网络使用。' : 'Auto-save from every device. Use only on a trusted network.';
  static String get defaultDestinationResolving => _isChinese ? '正在确定系统下载目录…' : 'Resolving Downloads folder…';
  static String get defaultDestinationUnavailable => _isChinese ? '无法确定默认保存目录' : 'Default save folder unavailable';
  static String get defaultPathHint => _isChinese ? '系统默认保存位置' : 'System default save location';
  static String get customPathHint => _isChinese ? '自定义保存位置' : 'Custom save location';
}
