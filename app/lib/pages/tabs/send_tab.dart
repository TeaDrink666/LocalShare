import 'package:collection/collection.dart';
import 'package:common/model/device.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/pages/selected_files_page.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/pages/troubleshoot_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/ui/nav_bar_padding.dart';
import 'package:localsend_app/widget/custom_progress_bar.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';
import 'package:localsend_app/widget/localshare_design/localshare_hero.dart';
import 'package:localsend_app/widget/localshare_design/localshare_surface.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _options = FilePickerOption.getOptionsForPlatform();

class SendTab extends StatelessWidget {
  const SendTab();

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: sendTabVmProvider,
      init: (context) async => context.global.dispatchAsync(SendTabInitAction(context)), // ignore: discarded_futures
      builder: (context, vm) {
        final ref = context.ref;
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 600 ? LocalShareSpacing.md : LocalShareSpacing.lg;

            return Scrollbar(
              child: SingleChildScrollView(
                primary: true,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        LocalShareSpacing.md,
                        horizontalPadding,
                        LocalShareSpacing.xl + getNavBarPadding(context),
                      ),
                      child: vm.selectedFiles.isEmpty
                          ? _ContentPicker(
                              onPick: (option) async => ref.global.dispatchAsync(
                                PickFileAction(
                                  option: option,
                                  context: context,
                                ),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SelectedFilesBar(
                                  files: vm.selectedFiles,
                                  onClear: () => ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction()),
                                  onEdit: () async {
                                    await context.push(
                                      () => const SelectedFilesPage(),
                                    );
                                  },
                                  onAdd: () async => _openAddFileDialog(context, ref),
                                ),
                                const SizedBox(height: LocalShareSpacing.lg),
                                _NearbyDevicesPanel(vm: vm),
                                const SizedBox(height: LocalShareSpacing.md),
                                _WebTransferEntry(
                                  onTap: () async => vm.onTapSendMode(
                                    context,
                                    SendMode.link,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _openAddFileDialog(BuildContext context, Ref ref) async {
  if (_options.length == 1) {
    await ref.global.dispatchAsync(
      PickFileAction(option: _options.first, context: context),
    );
    return;
  }
  await AddFileDialog.open(context: context, options: _options);
}

class _ContentPicker extends StatelessWidget {
  const _ContentPicker({required this.onPick});

  final Future<void> Function(FilePickerOption option) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LocalShareCard(
      padding: const EdgeInsets.all(LocalShareSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '选择要发送的内容',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: LocalShareSpacing.xs),
          Text(
            '选完后再选附近设备或生成链接',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: LocalShareSpacing.lg),
          _PickerGrid(onPick: onPick),
        ],
      ),
    );
  }
}

class _PickerGrid extends StatelessWidget {
  const _PickerGrid({required this.onPick});

  final Future<void> Function(FilePickerOption option) onPick;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 3
            : constraints.maxWidth < 280 || (textScale > 1.35 && constraints.maxWidth < 440)
                ? 1
                : 2;
        const gap = LocalShareSpacing.sm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _options
              .map(
                (option) => SizedBox(
                  width: width,
                  child: _PickerOptionTile(
                    option: option,
                    onTap: () async => onPick(option),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _PickerOptionTile extends StatelessWidget {
  const _PickerOptionTile({required this.option, required this.onTap});

  final FilePickerOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LocalShareCard(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalShareSpacing.sm,
        vertical: LocalShareSpacing.sm,
      ),
      onTap: onTap,
      semanticLabel: '${option.label}，${_optionDescription(option)}',
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(LocalShareRadii.medium),
            ),
            child: Padding(
              padding: const EdgeInsets.all(LocalShareSpacing.xs),
              child: Icon(
                option.icon,
                size: 23,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: LocalShareSpacing.sm),
          Expanded(
            child: Text(
              option.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

String _optionDescription(FilePickerOption option) {
  return switch (option) {
    FilePickerOption.file => '选择一个或多个文件',
    FilePickerOption.folder => '发送整个文件夹',
    FilePickerOption.media => '选择照片或视频',
    FilePickerOption.text => '输入一段文字消息',
    FilePickerOption.app => '选择应用安装包',
    FilePickerOption.clipboard => '读取剪贴板内容',
  };
}

class _SelectedFilesBar extends StatelessWidget {
  const _SelectedFilesBar({
    required this.files,
    required this.onClear,
    required this.onEdit,
    required this.onAdd,
  });

  final List<CrossFile> files;
  final VoidCallback onClear;
  final Future<void> Function() onEdit;
  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSize = files.fold<int>(0, (total, file) => total + file.size);
    return LocalShareCard(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalShareSpacing.sm,
        vertical: LocalShareSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(LocalShareRadii.medium),
            ),
            child: Icon(
              Icons.inventory_2_rounded,
              size: 21,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: LocalShareSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '已选择 ${files.length} 项',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  totalSize.asReadableFileSize,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '添加内容',
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '编辑已选内容',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '清空已选内容',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _WebTransferEntry extends StatelessWidget {
  const _WebTransferEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LocalShareCard(
      padding: const EdgeInsets.symmetric(
        horizontal: LocalShareSpacing.md,
        vertical: LocalShareSpacing.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(LocalShareRadii.medium),
            ),
            child: Icon(
              Icons.link_rounded,
              size: 21,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: LocalShareSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '通过链接发送',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: LocalShareSpacing.xxs),
                Text(
                  '接收端打开链接或扫码，无需安装软件',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: LocalShareSpacing.xs),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _NearbyDevicesPanel extends StatelessWidget {
  const _NearbyDevicesPanel({required this.vm});

  final SendTabVm vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '附近设备',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: LocalShareSpacing.xxs),
                  Text(
                    vm.nearbyDevices.isEmpty ? '正在搜索同一局域网内的设备' : '${vm.nearbyDevices.length} 台设备可用',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: LocalShareSpacing.xs),
            _ScanButton(ips: vm.localIps),
            _NearbyMoreMenu(vm: vm),
          ],
        ),
        const SizedBox(height: LocalShareSpacing.md),
        if (vm.nearbyDevices.isEmpty)
          const _NearbyEmptyState()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 2 : 1;
              const gap = LocalShareSpacing.sm;
              final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: vm.nearbyDevices.map((device) {
                  final favoriteEntry = vm.favoriteDevices.findDevice(device);
                  return SizedBox(
                    width: itemWidth,
                    child: vm.sendMode == SendMode.multiple
                        ? _MultiSendDeviceListTile(
                            device: device,
                            isFavorite: favoriteEntry != null,
                            nameOverride: favoriteEntry?.alias,
                            vm: vm,
                          )
                        : _ModernDeviceTile(
                            device: device,
                            isFavorite: favoriteEntry != null,
                            nameOverride: favoriteEntry?.alias,
                            onFavoriteTap: () async => vm.onToggleFavorite(context, device),
                            onTap: () async => vm.onTapDevice(context, device),
                          ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }
}

enum _NearbyMenuAction {
  address,
  favorites,
  toggleMultiple,
  troubleshoot,
}

class _NearbyMoreMenu extends StatelessWidget {
  const _NearbyMoreMenu({required this.vm});

  final SendTabVm vm;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NearbyMenuAction>(
      tooltip: '更多发送选项',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) async {
        switch (action) {
          case _NearbyMenuAction.address:
            await vm.onTapAddress(context);
          case _NearbyMenuAction.favorites:
            await vm.onTapFavorite(context);
          case _NearbyMenuAction.toggleMultiple:
            await vm.onTapSendMode(
              context,
              vm.sendMode == SendMode.multiple ? SendMode.single : SendMode.multiple,
            );
          case _NearbyMenuAction.troubleshoot:
            await context.push(() => const TroubleshootPage());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _NearbyMenuAction.address,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: Text(t.sendTab.manualSending),
          ),
        ),
        PopupMenuItem(
          value: _NearbyMenuAction.favorites,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.favorite_border_rounded),
            title: Text(t.dialogs.favoriteDialog.title),
          ),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: _NearbyMenuAction.toggleMultiple,
          checked: vm.sendMode == SendMode.multiple,
          child: Text(
            LocalShareCopy.isChinese ? '同时选择多个设备' : 'Select multiple devices',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _NearbyMenuAction.troubleshoot,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(t.troubleshootPage.title),
          ),
        ),
      ],
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (scanningFavorites, scanningIps) = context.ref.watch(
      nearbyDevicesProvider.select((state) => (state.runningFavoriteScan, state.runningIps)),
    );
    final scanning = scanningFavorites || scanningIps.isNotEmpty;

    return LocalShareSurface(
      style: LocalShareSurfaceStyle.subtle,
      padding: const EdgeInsets.all(LocalShareSpacing.md),
      child: Row(
        children: [
          if (scanning)
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: theme.colorScheme.primary,
              ),
            )
          else
            Icon(
              Icons.radar_rounded,
              color: theme.colorScheme.primary,
            ),
          const SizedBox(width: LocalShareSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  scanning ? '正在搜索…' : '未发现附近设备',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: LocalShareSpacing.xxs),
                Text(
                  '请确认两台设备连接到同一局域网',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _runSmartScan(BuildContext context) async {
  context.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
  await context.global.dispatchAsync(StartSmartScan(forceLegacy: true));
}

/// A button that opens a popup menu to select [T].
class _CircularPopupButton<T> extends StatelessWidget {
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget child;

  const _CircularPopupButton({
    required this.tooltip,
    required this.onSelected,
    required this.itemBuilder,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LocalShareRadii.full),
        child: Material(
          type: MaterialType.transparency,
          child: DividerTheme(
            data: DividerThemeData(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            child: PopupMenuButton(
              offset: const Offset(0, 44),
              onSelected: onSelected,
              tooltip: tooltip,
              itemBuilder: itemBuilder,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The scan button that uses [_CircularPopupButton].
class _ScanButton extends StatelessWidget {
  final List<String> ips;

  const _ScanButton({
    required this.ips,
  });

  @override
  Widget build(BuildContext context) {
    final (scanningFavorites, scanningIps) = context.ref.watch(nearbyDevicesProvider.select((s) => (s.runningFavoriteScan, s.runningIps)));
    final animations = context.ref.watch(animationProvider);

    final spinning = (scanningFavorites || scanningIps.isNotEmpty) && animations;
    final iconColor = !animations && scanningIps.isNotEmpty ? Theme.of(context).colorScheme.warning : null;

    if (ips.length <= StartSmartScan.maxInterfaces) {
      return IconButton(
        tooltip: t.sendTab.scan,
        onPressed: () async => _runSmartScan(context),
        icon: RotatingWidget(
          duration: const Duration(seconds: 2),
          spinning: spinning,
          reverse: true,
          child: Icon(Icons.sync_rounded, color: iconColor),
        ),
      );
    }

    return _CircularPopupButton(
      tooltip: t.sendTab.scan,
      onSelected: (ip) async {
        context.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
        await context.global.dispatchAsync(StartLegacySubnetScan(subnets: [ip]));
      },
      itemBuilder: (_) {
        return [
          ...ips.map(
            (ip) => PopupMenuItem(
              value: ip,
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RotatingSyncIcon(ip),
                  const SizedBox(width: 10),
                  Text(ip),
                ],
              ),
            ),
          ),
        ];
      },
      child: Padding(
        padding: const EdgeInsets.all(LocalShareSpacing.sm),
        child: RotatingWidget(
          duration: const Duration(seconds: 2),
          spinning: spinning,
          reverse: true,
          child: Icon(Icons.sync_rounded, color: iconColor),
        ),
      ),
    );
  }
}

/// A separate widget, so it gets the latest data from provider.
class _RotatingSyncIcon extends StatelessWidget {
  final String ip;

  const _RotatingSyncIcon(this.ip);

  @override
  Widget build(BuildContext context) {
    final scanningIps = context.ref.watch(nearbyDevicesProvider.select((s) => s.runningIps));
    return RotatingWidget(
      duration: const Duration(seconds: 2),
      spinning: scanningIps.contains(ip),
      reverse: true,
      child: const Icon(Icons.sync),
    );
  }
}

class _ModernDeviceTile extends StatelessWidget {
  const _ModernDeviceTile({
    required this.device,
    required this.isFavorite,
    required this.nameOverride,
    required this.onTap,
    required this.onFavoriteTap,
    this.info,
    this.progress,
  });

  final Device device;
  final bool isFavorite;
  final String? nameOverride;
  final String? info;
  final double? progress;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LocalShareCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(LocalShareSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(LocalShareRadii.medium),
              ),
              child: Icon(
                device.deviceType.icon,
                size: 23,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: LocalShareSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nameOverride ?? device.alias,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: LocalShareSpacing.xxs),
                  if (info != null)
                    Text(
                      info!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    )
                  else if (progress != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 2, top: 2),
                      child: CustomProgressBar(progress: progress!),
                    )
                  else
                    Text(
                      [
                        '#${device.ip.visualId}',
                        if (device.deviceModel != null) device.deviceModel!,
                      ].join('  ·  '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: isFavorite ? '取消收藏' : '收藏设备',
              onPressed: onFavoriteTap,
              icon: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFavorite ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An advanced list tile which shows the progress of the file transfer.
class _MultiSendDeviceListTile extends StatelessWidget {
  final Device device;
  final bool isFavorite;
  final String? nameOverride;
  final SendTabVm vm;

  const _MultiSendDeviceListTile({
    required this.device,
    required this.isFavorite,
    required this.nameOverride,
    required this.vm,
  });

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final session = ref.watch(sendProvider).values.firstWhereOrNull((s) => s.target.ip == device.ip);
    final double? progress;
    if (session != null) {
      final files = session.files.values.where((f) => f.token != null);
      final progressNotifier = ref.watch(progressProvider);
      final currBytes = files.fold<int>(
          0, (prev, curr) => prev + ((progressNotifier.getProgress(sessionId: session.sessionId, fileId: curr.file.id) * curr.file.size).round()));
      final totalBytes = files.fold<int>(0, (prev, curr) => prev + curr.file.size);
      progress = totalBytes == 0 ? 0 : currBytes / totalBytes;
    } else {
      progress = null;
    }
    return _ModernDeviceTile(
      device: device,
      info: session?.status.humanString,
      progress: progress,
      isFavorite: isFavorite,
      nameOverride: nameOverride,
      onFavoriteTap: () async => await vm.onToggleFavorite(context, device),
      onTap: () async => await vm.onTapDeviceMultiSend(context, device),
    );
  }
}

extension on SessionStatus {
  String? get humanString {
    switch (this) {
      case SessionStatus.waiting:
        return t.sendPage.waiting;
      case SessionStatus.recipientBusy:
        return t.sendPage.busy;
      case SessionStatus.declined:
        return t.sendPage.rejected;
      case SessionStatus.tooManyAttempts:
        return t.sendPage.tooManyAttempts;
      case SessionStatus.sending:
        return null;
      case SessionStatus.finished:
        return t.general.finished;
      case SessionStatus.finishedWithErrors:
        return t.progressPage.total.title.finishedError;
      case SessionStatus.canceledBySender:
        return t.progressPage.total.title.canceledSender;
      case SessionStatus.canceledByReceiver:
        return t.progressPage.total.title.canceledReceiver;
    }
  }
}
