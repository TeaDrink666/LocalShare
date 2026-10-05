import 'package:localsend_app/features/tasks/transfer_task.dart';

/// Shared progress calculation for the dashboard and task details.
class TaskProgressTracker {
  final _samples = <String, List<(int, int)>>{};

  TaskProgressSnapshot measure(TransferTask task, double Function(String fileId) progress, int now) {
    var bytes = 0;
    for (final file in task.files) {
      final size = file['size'] as int;
      bytes += file['status'] == 'finished'
          ? size
          : (progress(file['id'] as String) * size).round().clamp((file['receivedBytes'] as int? ?? 0).clamp(0, size), size);
    }
    if (task.stage == TransferTaskStage.completed) bytes = task.totalBytes;
    final samples = _samples.putIfAbsent(task.id, () => []);
    // A retry can restart progress. Do not include an earlier run in its speed.
    if (samples.isNotEmpty && bytes < samples.last.$2) samples.clear();
    if (samples.isEmpty || now - samples.last.$1 >= 1000) {
      samples.add((now, bytes));
    }
    samples.removeWhere((sample) => now - sample.$1 > 10000);
    final speed = samples.length > 1 && samples.last.$1 > samples.first.$1
        ? ((samples.last.$2 - samples.first.$2) * 1000 / (samples.last.$1 - samples.first.$1)).clamp(0, double.infinity).round()
        : 0;
    return TaskProgressSnapshot(
      bytes: bytes,
      speed: speed,
      elapsed: task.startedAt == null ? 0 : (((task.endedAt ?? now) - task.startedAt!) ~/ 1000).clamp(0, 1 << 31),
      remaining: task.stage == TransferTaskStage.running && speed > 0 ? ((task.totalBytes - bytes).clamp(0, task.totalBytes) / speed).ceil() : null,
      fraction: task.totalBytes == 0 ? (task.stage == TransferTaskStage.completed ? 1.0 : 0.0) : (bytes / task.totalBytes).clamp(0.0, 1.0),
    );
  }
}

class TaskProgressSnapshot {
  const TaskProgressSnapshot({required this.bytes, required this.speed, required this.elapsed, required this.remaining, required this.fraction});
  final int bytes;
  final int speed;
  final int elapsed;
  final int? remaining;
  final double fraction;
}
