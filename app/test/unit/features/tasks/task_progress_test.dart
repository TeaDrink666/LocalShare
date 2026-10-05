import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/features/tasks/task_progress.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';

void main() {
  test('progress preserves resume checkpoint and estimates remaining time from recent samples', () {
    final tracker = TaskProgressTracker();
    final task = _task(TransferTaskStage.running);
    final first = tracker.measure(task, (_) => 0.1, 10000);
    expect(first.bytes, 400);
    expect(first.fraction, 0.4);
    expect(first.remaining, isNull);
    final next = tracker.measure(task, (_) => 0.6, 12000);
    expect(next.speed, 100);
    expect(next.remaining, 4);
    expect(next.elapsed, 12);
  });
  test('completed tasks show full progress and retry does not reuse old speed', () {
    final tracker = TaskProgressTracker();
    tracker.measure(_task(TransferTaskStage.running), (_) => 0.8, 10000);
    final retry = tracker.measure(_task(TransferTaskStage.running), (_) => 0.4, 11000);
    expect(retry.speed, 0);
    final completed = tracker.measure(_task(TransferTaskStage.completed), (_) => 0, 12000);
    expect(completed.fraction, 1);
    expect(completed.bytes, 1000);
    expect(completed.remaining, isNull);
  });
}

TransferTask _task(TransferTaskStage stage) =>
    TransferTask(id: 'task', kind: TransferTaskKind.receive, peer: 'phone', createdAt: 0, startedAt: 0, stage: stage, files: const [
      {'id': 'file', 'name': 'file', 'size': 1000, 'status': 'sending', 'receivedBytes': 400}
    ]);
