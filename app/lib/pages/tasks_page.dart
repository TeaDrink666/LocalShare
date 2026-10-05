import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/tasks/task_progress.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';

String taskText(String zh, String en) => LocalShareCopy.isChinese ? zh : en;
String taskStageLabel(TransferTaskStage stage) => switch (stage) {
      TransferTaskStage.queued => taskText('排队中', 'Queued'),
      TransferTaskStage.waiting => taskText('等待接受', 'Waiting for acceptance'),
      TransferTaskStage.running => taskText('传输中', 'Transferring'),
      TransferTaskStage.verifying => taskText('校验并保存确认记录', 'Verifying and saving receipt'),
      TransferTaskStage.paused => taskText('已暂停', 'Paused'),
      TransferTaskStage.interrupted => taskText('已中断，可继续', 'Interrupted'),
      TransferTaskStage.completed => taskText('已完成', 'Completed'),
      TransferTaskStage.failed => taskText('失败，可重试', 'Failed'),
      TransferTaskStage.canceled => taskText('已取消', 'Canceled'),
    };
String taskKindLabel(TransferTaskKind kind) => switch (kind) {
      TransferTaskKind.send => taskText('发送', 'Send'),
      TransferTaskKind.receive => taskText('接收', 'Receive'),
      TransferTaskKind.backup => taskText('媒体同步', 'Media sync'),
    };
String taskDuration(int seconds) =>
    '${seconds ~/ 3600 > 0 ? '${seconds ~/ 3600}:' : ''}${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.taskId});
  final String? taskId;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  Timer? _timer;
  int _filter = 0;
  final _tracker = TaskProgressTracker();
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = context.watch(taskProvider);
    final progress = context.watch(progressProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    final tasks = center.tasks.values
        .where((task) => widget.taskId == null || task.id == widget.taskId)
        .where((task) => _filter == 0 || (_filter == 1 ? !task.autoClearable : task.autoClearable))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(title: Text(taskText('任务', 'Tasks')), actions: [
        if (widget.taskId == null)
          IconButton(
            key: const Key('tasks-received-files'),
            tooltip: taskText('接收文件', 'Received files'),
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () async => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceiveHistoryPage())),
          ),
        if (widget.taskId == null)
          IconButton(
              tooltip: taskText('清除已完成和已取消记录', 'Clear finished history'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => context.ref.notifier(taskProvider).clearFinished()),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.taskId == null) ...[
          Text(taskText('最多同时 ${center.limit} 个传输任务；媒体同步最多 1 个', 'Up to ${center.limit} simultaneous transfers; one media sync')),
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              children: List.generate(
                  3,
                  (index) => ChoiceChip(
                      label: Text([taskText('全部', 'All'), taskText('进行中 / 待恢复', 'Active / recoverable'), taskText('历史', 'History')][index]),
                      selected: _filter == index,
                      onSelected: (_) => setState(() => _filter = index)))),
          const SizedBox(height: 12),
        ],
        if (tasks.isEmpty) Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(taskText('暂无任务', 'No tasks')))),
        for (final task in tasks) _taskCard(context, task, progress, now),
      ]),
    );
  }

  Widget _taskCard(BuildContext context, TransferTask task, ProgressNotifier progress, int now) {
    final metric = _tracker.measure(task, (id) => progress.getProgress(sessionId: task.id, fileId: id), now);
    final bytes = metric.bytes;
    final speed = metric.speed;
    final elapsed = metric.elapsed;
    final remaining = metric.remaining == null ? '—' : taskDuration(metric.remaining!);
    final fraction = metric.fraction;
    final outgoing = task.retryData['target'] != null;
    return Card(
        child: InkWell(
      onTap: widget.taskId == null
          ? () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TasksPage(taskId: task.id)));
            }
          : null,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(task.kind == TransferTaskKind.receive
                  ? Icons.download_rounded
                  : task.kind == TransferTaskKind.backup
                      ? Icons.backup_rounded
                      : Icons.upload_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text('${taskKindLabel(task.kind)} · ${task.peer}', style: Theme.of(context).textTheme.titleMedium)),
            ]),
            Text(taskStageLabel(task.stage)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction),
            const SizedBox(height: 8),
            Text(
                '${(fraction * 100).toStringAsFixed(1)}% · ${bytes.asReadableFileSize} / ${task.totalBytes.asReadableFileSize} · ${task.files.length} ${taskText('个文件', 'files')}'),
            Text(
                '${taskText('已用', 'Elapsed')} ${taskDuration(elapsed.clamp(0, 1 << 31))} · ${taskText('预计剩余', 'Remaining')} $remaining${speed > 0 && task.stage == TransferTaskStage.running ? ' · ${speed.asReadableFileSize}/s' : ''}'),
            if (task.error != null) Text(task.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!outgoing && {TransferTaskStage.paused, TransferTaskStage.interrupted}.contains(task.stage))
              Text(taskText('等待发送设备重新连接并继续任务', 'Waiting for the sender to reconnect and resume')),
            if (widget.taskId != null) ...[
              const Divider(),
              if (task.directory != null) SelectableText(task.directory!),
              for (final file in task.files)
                ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(file['name'] as String),
                    subtitle: file['error'] == null ? null : Text(file['error'] as String),
                    trailing: file['status'] == 'finished' && file['path'] is String
                        ? PopupMenuButton<String>(
                            key: ValueKey('task-file-actions-${file['id']}'),
                            tooltip: taskText('文件操作', 'File actions'),
                            itemBuilder: (_) => [
                                  PopupMenuItem(value: 'open', child: Text(taskText('打开文件', 'Open file'))),
                                  if (!(file['path'] as String).startsWith('content://'))
                                    PopupMenuItem(value: 'folder', child: Text(taskText('在文件夹中显示', 'Show in folder'))),
                                ],
                            onSelected: (action) async {
                              final path = file['path'] as String;
                              if (action == 'open') {
                                await openFile(context, path.guessFileType(), path);
                              } else {
                                await openFolder(folderPath: p.dirname(path), fileName: p.basename(path));
                              }
                            })
                        : Text(file['status'] as String? ?? 'queue')),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (!outgoing && task.stage == TransferTaskStage.waiting) ...[
                FilledButton(onPressed: () => context.ref.notifier(taskProvider).accept(task.id), child: Text(taskText('接受', 'Accept'))),
                TextButton(onPressed: () => context.ref.notifier(taskProvider).decline(task.id), child: Text(taskText('拒绝', 'Decline'))),
              ],
              if (outgoing && {TransferTaskStage.running, TransferTaskStage.waiting, TransferTaskStage.queued}.contains(task.stage))
                TextButton(onPressed: () => context.ref.notifier(taskProvider).pause(task.id), child: Text(taskText('暂停', 'Pause'))),
              if (outgoing && {TransferTaskStage.paused, TransferTaskStage.interrupted, TransferTaskStage.failed}.contains(task.stage))
                FilledButton(
                    onPressed: () async {
                      try {
                        await context.ref.notifier(sendProvider).retryStoredTask(task.id);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                        }
                      }
                    },
                    child: Text(taskText('继续 / 重试', 'Resume / retry'))),
              if (!task.terminal && task.stage != TransferTaskStage.verifying)
                TextButton(onPressed: () => context.ref.notifier(taskProvider).cancel(task.id), child: Text(taskText('取消任务', 'Cancel task'))),
              if (task.directory != null)
                TextButton(
                    onPressed: () async {
                      await openFolder(folderPath: task.directory!);
                    },
                    child: Text(taskText('打开目录', 'Open folder'))),
              if (task.terminal)
                TextButton(onPressed: () => context.ref.notifier(taskProvider).remove(task.id), child: Text(taskText('清除记录', 'Remove history'))),
            ]),
          ])),
    ));
  }
}

class TaskSettingsPanel extends StatelessWidget {
  const TaskSettingsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final center = context.watch(taskProvider);
    return Card(
        child: Column(children: [
      ListTile(leading: const Icon(Icons.list_alt_rounded), title: Text(taskText('任务', 'Tasks'))),
      ListTile(
          title: Text(taskText('最大同时传输任务数', 'Maximum simultaneous transfers')),
          subtitle: Text(taskText('媒体同步固定最多 1 个任务', 'Media sync is limited to one task')),
          trailing: DropdownButton<int>(
              value: center.limit,
              items: List.generate(8, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
              onChanged: (value) async {
                if (value != null) {
                  await context.ref.notifier(taskProvider).setLimit(value);
                }
              })),
      ListTile(
          title: Text(taskText('自动清理已完成 / 已取消记录', 'Auto-clear completed / canceled history')),
          subtitle: Text(taskText('暂停和中断任务保留续传数据', 'Paused and interrupted tasks retain resume data')),
          trailing: DropdownButton<int>(
              value: center.retentionDays,
              items: [7, 30, 90, 0]
                  .map((days) => DropdownMenuItem(value: days, child: Text(days == 0 ? taskText('永久', 'Forever') : '$days ${taskText('天', 'days')}')))
                  .toList(),
              onChanged: (value) async {
                if (value != null) {
                  await context.ref.notifier(taskProvider).setRetention(value);
                }
              })),
    ]));
  }
}
