import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/tasks/task_progress.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/pages/tasks_page.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:localsend_app/widget/receive_mode_menu.dart';
import 'package:refena_flutter/refena_flutter.dart';

final dashboardDevicesProvider = ViewProvider((ref) => ref.watch(nearbyDevicesProvider));

enum _WebTransfer { send, receive }

/// Actions first, followed by incoming requests, live tasks and nearby devices.
class DashboardPage extends StatefulWidget {
  final Future<void> Function() onOpenNativeTransfer;
  final Future<void> Function() onOpenWebTransfer;
  final Future<void> Function() onOpenWebReceive;
  final Future<void> Function() onOpenBackup;
  final Future<void> Function() onOpenTasks;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onRefreshDevices;
  final bool embedded;

  const DashboardPage({
    required this.onOpenNativeTransfer,
    required this.onOpenWebTransfer,
    required this.onOpenWebReceive,
    required this.onOpenBackup,
    required this.onOpenTasks,
    required this.onOpenSettings,
    required this.onRefreshDevices,
    this.embedded = false,
    super.key,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _timer;
  final _tracker = TaskProgressTracker();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && TickerMode.of(context)) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(receiveTabVmProvider);
    final center = context.watch(taskProvider);
    final progress = context.watch(progressProvider);
    final devices = context.watch(dashboardDevicesProvider);
    final all = center.tasks.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final incoming = all.where((task) => task.stage == TransferTaskStage.waiting && task.retryData['target'] == null).toList();
    final active = all.where((task) => !task.terminal && !incoming.contains(task)).toList();
    final recoverable = all.where((task) => {TransferTaskStage.failed, TransferTaskStage.interrupted}.contains(task.stage)).length;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now().millisecondsSinceEpoch;

    final body = ListView(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 12 : 24, 16, 28),
      children: [
        Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(LocalShareCopy.home, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(vm.serverState?.alias ?? vm.aliasSettings,
                    style: Theme.of(context).textTheme.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
              IconButton(
                  key: const Key('dashboard-device-details'),
                  tooltip: taskText('设备与网络信息', 'Device and network info'),
                  onPressed: () async => _showDeviceInfo(vm),
                  icon: const Icon(Icons.info_outline_rounded)),
            ]),
            Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: vm.serverState == null ? scheme.outline : Colors.green),
                const SizedBox(width: 6),
                Flexible(
                    child: Text(vm.serverState == null ? taskText('接收服务未启动', 'Offline') : taskText('可以接收', 'Ready to receive'),
                        style: TextStyle(color: scheme.onSurfaceVariant))),
              ]),
              const ReceiveModeMenu(),
            ]),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 660 ? 3 : 1;
              final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(spacing: 12, runSpacing: 10, children: [
                SizedBox(
                    width: width,
                    child: _ActionCard(
                        key: const Key('dashboard-send-action'),
                        icon: Icons.send_rounded,
                        title: taskText('发送文件', 'Send files'),
                        subtitle: taskText('选择文件，发送到附近设备', 'Send to nearby devices'),
                        primary: true,
                        onTap: widget.onOpenNativeTransfer)),
                SizedBox(
                    width: width,
                    child: _ActionCard(
                        key: const Key('dashboard-web-action'),
                        icon: Icons.language_rounded,
                        title: taskText('网页传输', 'Web transfer'),
                        subtitle: taskText('通过浏览器发送或接收', 'Browser upload / download'),
                        onTap: _chooseWebTransfer)),
                SizedBox(
                    width: width,
                    child: _ActionCard(
                        key: const Key('dashboard-backup-shortcut'),
                        icon: Icons.photo_library_rounded,
                        title: taskText('媒体同步', 'Media sync'),
                        subtitle: taskText('备份手机新增照片和视频', 'Phone photos and videos'),
                        onTap: widget.onOpenBackup)),
              ]);
            }),
            if (incoming.isNotEmpty) ...[
              const SizedBox(height: 20),
              for (final task in incoming) Padding(padding: const EdgeInsets.only(bottom: 10), child: _incomingRequest(task)),
            ],
            const SizedBox(height: 24),
            _SectionTitle(
                title: taskText('当前任务', 'Current tasks'),
                action: TextButton(key: const Key('dashboard-all-tasks'), onPressed: widget.onOpenTasks, child: Text(taskText('全部任务', 'All tasks')))),
            if (active.isEmpty)
              LocalShareSurface(
                  style: LocalShareSurfaceStyle.subtle,
                  child: Row(children: [
                    Icon(Icons.task_alt_rounded, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(incoming.isEmpty
                            ? taskText('暂无进行中的任务', 'No active tasks')
                            : taskText('接收请求正在等待确认', 'Incoming requests await confirmation'))),
                  ]))
            else
              for (final task in active.take(3))
                Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _taskPreview(task, _tracker.measure(task, (id) => progress.getProgress(sessionId: task.id, fileId: id), now))),
            if (active.length > 3 || recoverable > 0)
              TextButton(
                  onPressed: widget.onOpenTasks,
                  child: Text(taskText(
                      '${active.length > 3 ? '还有 ${active.length - 3} 个任务。' : ''}${recoverable > 0 ? '$recoverable 个任务可恢复或重试' : '查看全部任务'}',
                      '${active.length > 3 ? '${active.length - 3} more tasks. ' : ''}${recoverable > 0 ? '$recoverable tasks can be resumed or retried' : 'View all tasks'}'))),
            const SizedBox(height: 18),
            _SectionTitle(
                title: taskText('附近设备', 'Nearby devices'),
                action: TextButton.icon(
                    key: const Key('dashboard-refresh-devices'),
                    onPressed: _refreshing || devices.runningFavoriteScan || devices.runningIps.isNotEmpty ? null : _refreshDevices,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(taskText('刷新', 'Refresh')))),
            _nearbyDevices(devices),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 4, children: [
              TextButton.icon(
                  key: const Key('dashboard-open-receive-folder'),
                  onPressed: _openReceiveFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(taskText('打开接收目录', 'Open receive folder'))),
              TextButton.icon(
                  onPressed: widget.onOpenSettings,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(taskText('接收设置', 'Receive settings'))),
            ]),
          ]),
        ))
      ],
    );
    return widget.embedded ? body : Scaffold(body: SafeArea(child: body));
  }

  Widget _incomingRequest(TransferTask task) => LocalShareSurface(
        key: ValueKey('incoming-${task.id}'),
        style: LocalShareSurfaceStyle.tinted,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.downloading_rounded),
            const SizedBox(width: 10),
            Expanded(child: Text(taskText('${task.peer} 请求发送文件', '${task.peer} wants to send files'), style: Theme.of(context).textTheme.titleMedium))
          ]),
          const SizedBox(height: 6),
          Text('${task.files.length} ${taskText('个文件', 'files')} · ${task.totalBytes.asReadableFileSize}'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilledButton(
                key: ValueKey('accept-${task.id}'),
                onPressed: () => context.ref.notifier(taskProvider).accept(task.id),
                child: Text(taskText('接受', 'Accept'))),
            TextButton(
                key: ValueKey('decline-${task.id}'),
                onPressed: () => context.ref.notifier(taskProvider).decline(task.id),
                child: Text(taskText('拒绝', 'Decline'))),
            TextButton(onPressed: () async => _openTask(task.id), child: Text(taskText('查看详情', 'Details'))),
          ]),
        ]),
      );

  Widget _taskPreview(TransferTask task, TaskProgressSnapshot metric) => LocalShareSurface(
        key: ValueKey('dashboard-task-${task.id}'),
        onTap: () async => _openTask(task.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                task.kind == TransferTaskKind.receive
                    ? Icons.download_rounded
                    : task.kind == TransferTaskKind.backup
                        ? Icons.photo_library_rounded
                        : Icons.upload_rounded,
                size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text('${taskKindLabel(task.kind)} · ${task.peer}', style: Theme.of(context).textTheme.titleSmall)),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ]),
          const SizedBox(height: 6),
          Text(taskStageLabel(task.stage), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: metric.fraction),
          const SizedBox(height: 8),
          Text('${(metric.fraction * 100).toStringAsFixed(1)}% · ${metric.bytes.asReadableFileSize} / ${task.totalBytes.asReadableFileSize}'),
          Text(
              '${taskText('已用', 'Elapsed')} ${taskDuration(metric.elapsed)} · ${taskText('剩余', 'Remaining')} ${metric.remaining == null ? '—' : taskDuration(metric.remaining!)}${metric.speed > 0 && task.stage == TransferTaskStage.running ? ' · ${metric.speed.asReadableFileSize}/s' : ''}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _nearbyDevices(NearbyDevicesState state) {
    if (state.devices.isEmpty) {
      return LocalShareSurface(
          style: LocalShareSurfaceStyle.subtle,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_refreshing || state.runningFavoriteScan || state.runningIps.isNotEmpty
                ? taskText('正在查找设备…', 'Looking for devices…')
                : taskText('暂未发现附近设备', 'No nearby devices found')),
            const SizedBox(height: 4),
            Text(taskText('在另一台设备打开 LocalShare，并连接同一网络', 'Open LocalShare on another device on the same network'),
                style: Theme.of(context).textTheme.bodySmall),
          ]));
    }
    final devices = state.devices.values.toList()..sort((a, b) => a.alias.compareTo(b.alias));
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth >= 660 ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
      return Wrap(spacing: 12, runSpacing: 10, children: [
        for (final device in devices)
          SizedBox(
              width: width,
              child: LocalShareSurface(
                  onTap: widget.onOpenNativeTransfer,
                  child: Row(children: [
                    Icon(device.deviceType.icon),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(device.alias, style: Theme.of(context).textTheme.titleSmall),
                      Text(device.deviceModel ?? taskText('局域网设备', 'Local network device'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ])),
                    const Icon(Icons.chevron_right_rounded),
                  ]))),
      ]);
    });
  }

  Future<void> _chooseWebTransfer() async {
    final choice = await showDialog<_WebTransfer>(
        context: context,
        builder: (context) => SimpleDialog(
              title: Text(taskText('网页传输', 'Web transfer')),
              children: [
                SimpleDialogOption(
                    key: const Key('dashboard-web-send'),
                    onPressed: () => Navigator.pop(context, _WebTransfer.send),
                    child: ListTile(
                        leading: const Icon(Icons.upload_rounded),
                        title: Text(taskText('网页发送', 'Send via web')),
                        subtitle: Text(taskText('让其他设备通过浏览器下载文件', 'Let another device download your files in a browser')))),
                SimpleDialogOption(
                    key: const Key('dashboard-web-receive'),
                    onPressed: () => Navigator.pop(context, _WebTransfer.receive),
                    child: ListTile(
                        leading: const Icon(Icons.download_rounded),
                        title: Text(taskText('网页接收', 'Receive via web')),
                        subtitle: Text(taskText('让其他设备通过浏览器上传文件', 'Let another device upload files in a browser')))),
              ],
            ));
    if (!mounted) return;
    if (choice == _WebTransfer.send) await widget.onOpenWebTransfer();
    if (choice == _WebTransfer.receive) await widget.onOpenWebReceive();
  }

  Future<void> _showDeviceInfo(ReceiveTabVm vm) async {
    final settings = context.ref.read(settingsProvider);
    final edit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(taskText('设备与网络信息', 'Device and network info')),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(vm.serverState?.alias ?? vm.aliasSettings),
                const SizedBox(height: 12),
                SelectableText('IP: ${vm.localIps.isEmpty ? '—' : vm.localIps.join('\n')}'),
                Text('${taskText('端口', 'Port')}: ${vm.serverState?.port ?? settings.port}'),
                Text('HTTPS: ${(vm.serverState?.https ?? settings.https) ? taskText('开启', 'On') : taskText('关闭', 'Off')}'),
              ])),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text(LocalShareCopy.settings)),
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(taskText('关闭', 'Close')))
              ],
            ));
    if (mounted && edit == true) await widget.onOpenSettings();
  }

  Future<void> _refreshDevices() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefreshDevices();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openReceiveFolder() async {
    try {
      final configuredDestination = context.ref.read(settingsProvider).destination;
      final destination = configuredDestination ?? await getDefaultDestinationDirectory();
      await openFolder(folderPath: destination);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openTask(String id) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TasksPage(taskId: id)));
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.onTap, this.primary = false, super.key});
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) => LocalShareSurface(
        style: primary ? LocalShareSurfaceStyle.accent : LocalShareSurfaceStyle.standard,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, size: 26),
          const SizedBox(width: 14),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: primary ? Theme.of(context).colorScheme.onPrimary : null)),
            const SizedBox(height: 4),
            Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: primary ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.85) : null)),
          ])),
        ]),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});
  final String title;
  final Widget action;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        action,
      ]);
}
