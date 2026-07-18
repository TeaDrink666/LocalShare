import 'package:localsend_app/util/http_byte_range.dart';
import 'package:test/test.dart';

void main() {
  group('HttpByteRange.parse', () {
    group('missing header', () {
      test('returns null', () {
        expect(
          HttpByteRange.parse(null, resourceLength: 100),
          isNull,
        );
      });

      test('returns null even when the resource is empty', () {
        expect(
          HttpByteRange.parse(null, resourceLength: 0),
          isNull,
        );
      });
    });

    group('explicit ranges', () {
      test('resolves inclusive start and end positions', () {
        final range = HttpByteRange.parse('bytes=10-19', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 10, end: 19, contentLength: 10));
      });

      test('accepts a one-byte range', () {
        final range = HttpByteRange.parse('bytes=42-42', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 42, end: 42, contentLength: 1));
      });

      test('clamps an end beyond the resource', () {
        final range = HttpByteRange.parse('bytes=95-200', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 95, end: 99, contentLength: 5));
      });

      test('clamps an arbitrarily large end rather than overflowing', () {
        final range = HttpByteRange.parse(
          'bytes=1-999999999999999999999999999999999999999',
          resourceLength: 10,
        );

        expect(range,
            const HttpByteRangeExpectation(start: 1, end: 9, contentLength: 9));
      });

      test('accepts leading zeroes', () {
        final range =
            HttpByteRange.parse('bytes=0002-0004', resourceLength: 10);

        expect(range,
            const HttpByteRangeExpectation(start: 2, end: 4, contentLength: 3));
      });
    });

    group('open-ended ranges', () {
      test('selects from start through the final byte', () {
        final range = HttpByteRange.parse('bytes=90-', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 90, end: 99, contentLength: 10));
      });

      test('can select the final byte', () {
        final range = HttpByteRange.parse('bytes=99-', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 99, end: 99, contentLength: 1));
      });
    });

    group('suffix ranges', () {
      test('selects the requested number of final bytes', () {
        final range = HttpByteRange.parse('bytes=-20', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 80, end: 99, contentLength: 20));
      });

      test('selects the whole resource when suffix equals its length', () {
        final range = HttpByteRange.parse('bytes=-100', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 0, end: 99, contentLength: 100));
      });

      test('selects the whole resource when suffix exceeds its length', () {
        final range = HttpByteRange.parse('bytes=-101', resourceLength: 100);

        expect(
            range,
            const HttpByteRangeExpectation(
                start: 0, end: 99, contentLength: 100));
      });

      test('supports arbitrarily large suffix lengths', () {
        final range = HttpByteRange.parse(
          'bytes=-999999999999999999999999999999999999999',
          resourceLength: 3,
        );

        expect(range,
            const HttpByteRangeExpectation(start: 0, end: 2, contentLength: 3));
      });
    });

    group('range unit and whitespace', () {
      test('treats the bytes unit case-insensitively', () {
        final range = HttpByteRange.parse('ByTeS=0-0', resourceLength: 1);

        expect(range,
            const HttpByteRangeExpectation(start: 0, end: 0, contentLength: 1));
      });

      test('accepts HTTP optional whitespace around the field value', () {
        final range = HttpByteRange.parse('\t bytes=1-2 \t', resourceLength: 4);

        expect(range,
            const HttpByteRangeExpectation(start: 1, end: 2, contentLength: 2));
      });
    });

    group('malformed ranges', () {
      for (final header in <String>[
        '',
        ' ',
        'bytes=',
        'bytes=-',
        'bytes=1',
        'bytes=one-two',
        'bytes=+1-2',
        'bytes=1.0-2',
        'bytes= 1-2',
        'bytes=1 -2',
        'bytes=1- 2',
        'bytes =1-2',
        'items=1-2',
        'bytes=0-1,2-3',
        'bytes=0-1,',
        'bytes=0--1',
        'bytes==0-1',
        'bytes=0-1\n',
      ]) {
        test('rejects "$header"', () {
          expect(
            () => HttpByteRange.parse(header, resourceLength: 100),
            throwsA(isA<MalformedHttpByteRangeException>()),
          );
        });
      }

      test('rejects an end before the start', () {
        expect(
          () => HttpByteRange.parse('bytes=20-10', resourceLength: 100),
          throwsA(
            isA<MalformedHttpByteRangeException>()
                .having((error) => error.header, 'header', 'bytes=20-10')
                .having((error) => error.resourceLength, 'resourceLength', 100)
                .having((error) => error.reason, 'reason', contains('end')),
          ),
        );
      });
    });

    group('unsatisfiable ranges', () {
      test('rejects a start equal to the resource length', () {
        expect(
          () => HttpByteRange.parse('bytes=100-', resourceLength: 100),
          throwsA(isA<UnsatisfiableHttpByteRangeException>()),
        );
      });

      test('rejects a start beyond the resource length', () {
        expect(
          () => HttpByteRange.parse('bytes=101-200', resourceLength: 100),
          throwsA(isA<UnsatisfiableHttpByteRangeException>()),
        );
      });

      test('rejects an arbitrarily large start', () {
        expect(
          () => HttpByteRange.parse(
            'bytes=999999999999999999999999999999999999999-',
            resourceLength: 100,
          ),
          throwsA(isA<UnsatisfiableHttpByteRangeException>()),
        );
      });

      test('rejects a zero-length suffix', () {
        expect(
          () => HttpByteRange.parse('bytes=-0', resourceLength: 100),
          throwsA(
            isA<UnsatisfiableHttpByteRangeException>()
                .having((error) => error.header, 'header', 'bytes=-0')
                .having((error) => error.resourceLength, 'resourceLength', 100)
                .having((error) => error.reason, 'reason', contains('suffix')),
          ),
        );
      });

      for (final resourceLength in <int>[0, -1]) {
        test('rejects a request when resource length is $resourceLength', () {
          expect(
            () =>
                HttpByteRange.parse('bytes=0-', resourceLength: resourceLength),
            throwsA(isA<UnsatisfiableHttpByteRangeException>()),
          );
        });

        test('rejects a suffix request when resource length is $resourceLength',
            () {
          expect(
            () =>
                HttpByteRange.parse('bytes=-1', resourceLength: resourceLength),
            throwsA(isA<UnsatisfiableHttpByteRangeException>()),
          );
        });
      }
    });
  });
}

final class HttpByteRangeExpectation extends Matcher {
  const HttpByteRangeExpectation({
    required this.start,
    required this.end,
    required this.contentLength,
  });

  final int start;
  final int end;
  final int contentLength;

  @override
  Description describe(Description description) => description.add(
        'has start $start, end $end, and contentLength $contentLength',
      );

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      item is HttpByteRange &&
      item.start == start &&
      item.end == end &&
      item.contentLength == contentLength;
}
