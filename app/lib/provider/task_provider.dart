import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common/model/session_status.dart';
import 'package:localsend_app/features/tasks/resumable_file_store.dart';
import 'package:localsend_app/features/tasks/task_queue.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

final taskProvider = NotifierProvider<TaskService, TaskCenterState>((ref) => TaskService(ref.read(persistenceProvider)));

class TaskCenterState {
  const TaskCenterState({required this.tasks, this.limit = 2, this.retentionDays = 30});
  final Map<String, TransferTask> tasks;
  final int limit;
  final int retentionDays;
}

class TaskService extends Notifier<TaskCenterState> {
  TaskService(this.persistence);
  final PersistenceService persistence;
  late final TransferTaskQueue queue;
  final mediaJobs = TransferTaskQueue(limit: 1);
  final Map<String, Future<void> Function()> retries = {};
  final Map<String, void Function()> cancellations = {};
  final Map<String, void Function()> pauses = {};
  final Map<String, void Function()> acceptances = {};
  final Map<String, void Function()> declines = {};
  final Map<String, void Function()> disposals = {};
  void accept(String id) => acceptances[id]?.call();
  void decline(String id) => declines[id]?.call();
  Future<void> flush() => _writes;
  void checkpoint(String id, String fileId, int bytes) {
    final task = state.tasks[id];
    if (task == null) return;
    put(task.copyWith(
        stage: task.stage,
        files: task.files.map((file) => file['id'] == fileId ? {...file, 'receivedBytes': bytes} : file).toList(),
        error: task.error));
  }

  Future<void> _writes = Future.value();

  @override
  TaskCenterState init() {
    final tasks = <String, TransferTask>{};
    for (final raw in persistence.getTransferTasks()) {
      try {
        var task = TransferTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (!task.terminal && task.stage != TransferTaskStage.paused) {
          task = task.copyWith(stage: TransferTaskStage.interrupted, error: '应用已退出，可重新连接后继续');
        }
        tasks[task.id] = task;
      } on Object {/* Keep other valid records if one record is malformed. */}
    }
    final limit = persistence.getTaskConcurrency().clamp(1, 8);
    queue = TransferTaskQueue(limit: limit);
    final storedDays = persistence.getTaskRetentionDays();
    final days = [0, 7, 30, 90].contains(storedDays) ? storedDays : 30;
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    if (days > 0) {
      tasks.removeWhere((_, task) {
        final expired = task.autoClearable && (task.endedAt ?? task.createdAt) < cutoff;
        if (expired) {
          unawaited(_discardSavedData(task).catchError((Object _) {}));
        }
        return expired;
      });
    }
    return TaskCenterState(tasks: tasks, limit: limit, retentionDays: days);
  }

  void put(TransferTask task) {
    state = TaskCenterState(tasks: {...state.tasks, task.id: task}, limit: state.limit, retentionDays: state.retentionDays);
    _save();
  }

  void update(String id, TransferTaskStage stage, {String? error}) {
    final task = state.tasks[id];
    if (task != null) {
      put(task.copyWith(
          stage: stage,
          error: error,
          startedAt: stage == TransferTaskStage.running ? DateTime.now().millisecondsSinceEpoch : null,
          endedAt: {TransferTaskStage.completed, TransferTaskStage.failed, TransferTaskStage.canceled}.contains(stage)
              ? DateTime.now().millisecondsSinceEpoch
              : null));
    }
  }

  Future<void> setLimit(int value) async {
    queue.limit = value;
    state = TaskCenterState(tasks: state.tasks, limit: value, retentionDays: state.retentionDays);
    await persistence.setTaskConcurrency(value);
  }

  Future<void> setRetention(int days) async {
    if (![0, 7, 30, 90].contains(days)) throw ArgumentError.value(days);
    state = TaskCenterState(tasks: state.tasks, limit: state.limit, retentionDays: days);
    await persistence.setTaskRetentionDays(days);
    clearOld();
  }

  void clearOld() {
    if (state.retentionDays == 0) return;
    final cutoff = DateTime.now().subtract(Duration(days: state.retentionDays)).millisecondsSinceEpoch;
    _removeWhere((task) => task.autoClearable && (task.endedAt ?? task.createdAt) < cutoff);
  }

  void clearFinished() => _removeWhere((task) => task.autoClearable);
  void remove(String id) => _removeWhere((task) => task.id == id && task.terminal);
  void _removeWhere(bool Function(TransferTask) predicate) {
    for (final task in state.tasks.values.where(predicate).toList()) {
      disposals.remove(task.id)?.call();
      retries.remove(task.id);
      cancellations.remove(task.id);
      pauses.remove(task.id);
      acceptances.remove(task.id);
      declines.remove(task.id);
      unawaited(_discardSavedData(task).catchError((Object _) {}));
    }
    final tasks = {...state.tasks}..removeWhere((id, task) => predicate(task));
    state = TaskCenterState(tasks: tasks, limit: state.limit, retentionDays: state.retentionDays);
    _save();
  }

  Future<void> _discardSavedData(TransferTask task) async {
    final peer = task.retryData['fingerprint'] as String?;
    final sourceId = task.retryData['transferId'] as String?;
    if (peer == null || sourceId == null) return;
    final support = await getApplicationSupportDirectory();
    final store = ResumableFileStore(Directory(p.join(support.path, 'localshare-transfer-data')));
    for (final file in task.files) {
      await store.discard(store.key(peer, sourceId, file['id'] as String));
    }
  }

  void cancel(String id) {
    update(id, TransferTaskStage.canceled);
    queue.release(id);
    mediaJobs.release(id);
    cancellations[id]?.call();
  }

  void pause(String id) {
    update(id, TransferTaskStage.paused);
    pauses[id]?.call();
    queue.release(id);
    mediaJobs.release(id);
  }

  Future<void> retry(String id) async {
    final retry = retries[id];
    if (retry != null) await retry();
  }

  void syncSend(Map<String, SendSessionState> sessions) {
    for (final session in sessions.values) {
      final existing = state.tasks[session.sessionId];
      if (existing == null || existing.stage == TransferTaskStage.paused || existing.stage == TransferTaskStage.canceled) continue;
      put(existing.copyWith(
          stage: existing.kind == TransferTaskKind.backup && session.status == SessionStatus.finished
              ? TransferTaskStage.verifying
              : _stage(session.status),
          startedAt: session.startTime,
          endedAt: session.endTime,
          error: session.errorMessage,
          files: session.files.values
              .map((file) => <String, dynamic>{
                    'id': file.file.id,
                    'name': file.file.fileName,
                    'size': file.file.size,
                    'status': file.status.name,
                    'error': file.errorMessage,
                    'receivedBytes': _previousBytes(existing, file.file.id),
                  })
              .toList()));
    }
  }

  void syncReceive(ReceiveSessionState session) {
    final existing = state.tasks[session.sessionId];
    if (existing == null || existing.stage == TransferTaskStage.canceled || existing.stage == TransferTaskStage.paused) return;
    put(existing.copyWith(
        stage: session.status == SessionStatus.sending && existing.retryData['admission'] == true && !queue.isActive(session.sessionId)
            ? TransferTaskStage.queued
            : _stage(session.status),
        startedAt: session.startTime,
        endedAt: session.endTime,
        directory: session.destinationDirectory,
        files: session.files.values
            .map((file) => <String, dynamic>{
                  'id': file.file.id,
                  'name': file.file.fileName,
                  'size': file.file.size,
                  'status': file.status.name,
                  'path': file.path,
                  'error': file.errorMessage,
                  'receivedBytes': _previousBytes(existing, file.file.id),
                })
            .toList()));
  }

  TransferTaskStage _stage(SessionStatus status) => switch (status) {
        SessionStatus.waiting => TransferTaskStage.waiting,
        SessionStatus.recipientBusy => TransferTaskStage.queued,
        SessionStatus.sending => TransferTaskStage.running,
        SessionStatus.finished => TransferTaskStage.completed,
        SessionStatus.canceledBySender || SessionStatus.canceledByReceiver => TransferTaskStage.canceled,
        _ => TransferTaskStage.failed,
      };
  int _previousBytes(TransferTask task, String fileId) {
    for (final file in task.files) {
      if (file['id'] == fileId) return file['receivedBytes'] as int? ?? 0;
    }
    return 0;
  }

  void _save() {
    final snapshot = state.tasks.values.map((task) => jsonEncode(task.toJson())).toList();
    final previous = _writes;
    unawaited(_writes = _writeSnapshot(previous, snapshot));
    unawaited(_writes.catchError((Object _) {}));
  }

  Future<void> _writeSnapshot(Future<void> previous, List<String> snapshot) async {
    try {
      await previous;
    } on Object {/* A later snapshot can recover a failed write. */}
    await persistence.setTransferTasks(snapshot);
  }
}
