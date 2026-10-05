import 'dart:convert';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';
import '../../../mocks.mocks.dart';

TransferTask record(String id, TransferTaskStage stage, {int? endedAt}) =>
    TransferTask(id: id, kind: TransferTaskKind.send, peer: 'Peer', createdAt: 1, stage: stage, endedAt: endedAt, files: const [
      {'id': 'file', 'name': 'source/main.dart', 'size': 10, 'status': 'queue'}
    ]);

void main() {
  test('restores interrupted work and keeps recoverable history when pruning', () {
    final persistence = MockPersistenceService();
    when(persistence.getTaskConcurrency()).thenReturn(2);
    when(persistence.getTaskRetentionDays()).thenReturn(30);
    when(persistence.getTransferTasks()).thenReturn([
      'malformed',
      jsonEncode(record('running', TransferTaskStage.running).toJson()),
      jsonEncode(record('paused', TransferTaskStage.paused).toJson()),
      jsonEncode(record('completed', TransferTaskStage.completed, endedAt: 1).toJson()),
      jsonEncode(record('failed', TransferTaskStage.failed, endedAt: 1).toJson()),
    ]);
    final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    final service = container.notifier(taskProvider);
    expect(service.state.tasks.keys, ['running', 'paused', 'failed']);
    expect(service.state.tasks['running']!.stage, TransferTaskStage.interrupted);
    service.clearFinished();
    expect(service.state.tasks, hasLength(3));
  });
  test('cancellation clears a queued media job and settings are persisted', () async {
    final persistence = MockPersistenceService();
    when(persistence.getTaskConcurrency()).thenReturn(2);
    final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    final service = container.notifier(taskProvider);
    await service.mediaJobs.acquire('active', media: true);
    service.put(record('queued', TransferTaskStage.queued));
    final waiting = service.mediaJobs.acquire('queued', media: true);
    service.cancel('queued');
    expect(await waiting, isFalse);
    expect(service.state.tasks['queued']!.stage, TransferTaskStage.canceled);
    await service.setLimit(3);
    await service.setRetention(7);
    await service.flush();
    verify(persistence.setTaskConcurrency(3)).called(1);
    verify(persistence.setTaskRetentionDays(7)).called(1);
  });
}
