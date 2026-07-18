import 'dart:async';

import 'package:localsend_app/util/byte_stream_slice.dart';
import 'package:test/test.dart';

void main() {
  group('sliceByteStream', () {
    test('slices accurately across arbitrary chunk boundaries', () async {
      final result = await sliceByteStream(
        Stream.fromIterable(<List<int>>[
          [0, 1],
          [],
          [2, 3, 4, 5],
          [6],
          [7, 8, 9],
        ]),
        start: 3,
        length: 5,
      ).expand((chunk) => chunk).toList();

      expect(result, [3, 4, 5, 6, 7]);
    });

    test('cancels the source after the requested bytes', () async {
      var canceled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => canceled = true,
      );
      controller
        ..add([0, 1, 2, 3])
        ..add([4, 5, 6, 7]);

      final result = await sliceByteStream(
        controller.stream,
        start: 1,
        length: 2,
      ).expand((chunk) => chunk).toList();

      expect(result, [1, 2]);
      expect(canceled, isTrue);
      await controller.close();
    });

    test('reports a source that ends before the window is complete', () async {
      final result = sliceByteStream(
        Stream.value([0, 1, 2]),
        start: 2,
        length: 2,
      );

      await expectLater(result.toList(), throwsStateError);
    });

    test('rejects negative positions and lengths', () async {
      await expectLater(
        sliceByteStream(Stream.empty(), start: -1, length: 0).toList(),
        throwsRangeError,
      );
      await expectLater(
        sliceByteStream(Stream.empty(), start: 0, length: -1).toList(),
        throwsRangeError,
      );
    });
  });
}
