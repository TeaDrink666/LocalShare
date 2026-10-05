import 'dart:async';

/// Application-wide admission control. Media backups have an additional limit
/// of one; changing the limit never interrupts an admitted task.
class TransferTaskQueue {
  TransferTaskQueue({int limit = 2}) : _limit = limit;
  int _limit;
  final _active = <String, bool>{};
  final _waiting = <String, (bool, Completer<bool>)>{};

  int get activeCount => _active.length;
  int get waitingCount => _waiting.length;
  bool isActive(String id) => _active.containsKey(id);

  set limit(int value) {
    if (value < 1 || value > 8) throw RangeError.range(value, 1, 8);
    _limit = value;
    _drain();
  }

  Future<bool> acquire(String id, {bool media = false}) {
    if (_active.containsKey(id)) return Future.value(true);
    final existing = _waiting[id];
    if (existing != null) return existing.$2.future;
    final completer = Completer<bool>();
    _waiting[id] = (media, completer);
    _drain();
    return completer.future;
  }

  void release(String id) {
    _active.remove(id);
    final pending = _waiting.remove(id);
    if (pending != null && !pending.$2.isCompleted) pending.$2.complete(false);
    _drain();
  }

  void _drain() {
    for (final entry in _waiting.entries.toList()) {
      if (_active.length >= _limit) break;
      if (entry.value.$1 && _active.values.any((media) => media)) continue;
      _waiting.remove(entry.key);
      _active[entry.key] = entry.value.$1;
      entry.value.$2.complete(true);
    }
  }
}
