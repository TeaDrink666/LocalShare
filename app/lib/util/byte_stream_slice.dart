/// Returns exactly [length] bytes from [source], beginning after [start]
/// bytes have been discarded.
///
/// The input may use arbitrary chunk boundaries. The returned stream stops
/// listening as soon as the requested window has been emitted, which is
/// important for content URI streams backed by a native resource.
Stream<List<int>> sliceByteStream(
  Stream<List<int>> source, {
  required int start,
  required int length,
}) async* {
  if (start < 0) {
    throw RangeError.value(start, 'start', 'Must not be negative.');
  }
  if (length < 0) {
    throw RangeError.value(length, 'length', 'Must not be negative.');
  }
  if (length == 0) {
    return;
  }

  var bytesToSkip = start;
  var bytesToTake = length;

  await for (final chunk in source) {
    if (chunk.isEmpty) {
      continue;
    }

    if (bytesToSkip >= chunk.length) {
      bytesToSkip -= chunk.length;
      continue;
    }

    final chunkStart = bytesToSkip;
    bytesToSkip = 0;
    final available = chunk.length - chunkStart;
    final take = available < bytesToTake ? available : bytesToTake;
    final chunkEnd = chunkStart + take;

    if (chunkStart == 0 && chunkEnd == chunk.length) {
      yield chunk;
    } else {
      yield chunk.sublist(chunkStart, chunkEnd);
    }

    bytesToTake -= take;
    if (bytesToTake == 0) {
      return;
    }
  }

  throw StateError(
    'The byte stream ended before the requested window was complete '
    '(${length - bytesToTake}/$length bytes emitted).',
  );
}
