import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:localsend_app/features/web_transfer/streaming_zip_writer.dart';
import 'package:test/test.dart';

void main() {
  group('StreamingZipWriter', () {
    test('produces a standard ZIP accepted by an independent decoder',
        () async {
      final greeting = utf8.encode('Hello from LocalShare!');
      final binary = List<int>.generate(257, (index) => index & 0xff);
      final bytes = await _collect(
        streamZip([
          _entry(
            'notes/hello.txt',
            greeting,
            chunks: [
              greeting.sublist(0, 3),
              const [],
              greeting.sublist(3, 12),
              greeting.sublist(12),
            ],
          ),
          _entry('data/all-bytes.bin', binary),
          _entry('empty.dat', const []),
        ]),
      );

      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(
        archive.files.map((file) => file.name),
        ['notes/hello.txt', 'data/all-bytes.bin', 'empty.dat'],
      );
      expect(archive.findFile('notes/hello.txt')!.content, greeting);
      expect(archive.findFile('data/all-bytes.bin')!.content, binary);
      expect(archive.findFile('empty.dat')!.content, isEmpty);
      expect(archive.files, everyElement(isA<ArchiveFile>()));
      expect(archive.files.map((file) => file.compress), everyElement(isFalse));
    });

    test('preserves Unicode folder and file names as UTF-8', () async {
      final summerPhoto = utf8.encode('jpeg-placeholder');
      final familyVideo = utf8.encode('video-placeholder');
      final bytes = await _collect(
        streamZip([
          _entry('相册/杭州旅行/夏天🌻.jpg', summerPhoto),
          _entry('家族/2026/生日🎂/動画.mp4', familyVideo),
        ]),
      );

      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(archive.findFile('相册/杭州旅行/夏天🌻.jpg')!.content, summerPhoto);
      expect(archive.findFile('家族/2026/生日🎂/動画.mp4')!.content, familyVideo);

      final centralHeaderOffset = _indexOfSignature(bytes, 0x02014b50);
      final flags = _uint16(bytes, centralHeaderOffset + 8);
      expect(flags & 0x0800, 0x0800, reason: 'UTF-8 flag must be set.');
    });

    test('is independent of source chunk boundaries and ignores empty chunks',
        () async {
      final payload = List<int>.generate(1025, (index) => (index * 31) & 0xff);
      final fixedTime = DateTime(2026, 7, 12, 21, 42, 18);
      var opened = false;
      final byteByByte = StreamingZipEntry(
        name: 'camera/payload.bin',
        sizeBytes: payload.length,
        modifiedTime: fixedTime,
        open: () {
          opened = true;
          return Stream<List<int>>.fromIterable([
            const [],
            ...payload.map((byte) => [byte]),
            const [],
          ]);
        },
      );
      final stream = streamZip([byteByByte]);
      expect(opened, isFalse, reason: 'Entry streams must be opened lazily.');

      final fragmentedBytes = await _collect(stream);
      expect(opened, isTrue);
      final singleChunkBytes = await _collect(
        streamZip([
          StreamingZipEntry(
            name: 'camera/payload.bin',
            sizeBytes: payload.length,
            modifiedTime: fixedTime,
            open: () => Stream.value(payload),
          ),
        ]),
      );

      expect(fragmentedBytes, singleChunkBytes);
      expect(
        ZipDecoder()
            .decodeBytes(fragmentedBytes, verify: true)
            .files
            .single
            .content,
        payload,
      );
    });

    test('writes the standard CRC-32 into descriptor and central directory',
        () async {
      final payload = ascii.encode('123456789');
      const expectedCrc32 = 0xcbf43926;
      final bytes = await _collect(
        streamZip([
          StreamingZipEntry(
            name: 'crc.txt',
            sizeBytes: payload.length,
            expectedCrc32: expectedCrc32,
            open: () => Stream.fromIterable([
              payload.sublist(0, 2),
              payload.sublist(2, 7),
              payload.sublist(7),
            ]),
          ),
        ]),
      );

      final descriptorOffset = _indexOfSignature(bytes, 0x08074b50);
      final centralOffset = _indexOfSignature(bytes, 0x02014b50);
      expect(_uint32(bytes, descriptorOffset + 4), expectedCrc32);
      expect(_uint32(bytes, centralOffset + 16), expectedCrc32);
      expect(
        ZipDecoder().decodeBytes(bytes, verify: true).files.single.content,
        payload,
      );
    });

    test('fails when a known source CRC-32 does not match', () async {
      final future = _collect(
        streamZip([
          StreamingZipEntry(
            name: 'changed.jpg',
            sizeBytes: 3,
            expectedCrc32: 0,
            open: () => Stream.value([1, 2, 3]),
          ),
        ]),
      );

      await expectLater(
        future,
        throwsA(
          isA<StreamingZipCrcMismatchException>()
              .having((error) => error.name, 'name', 'changed.jpg')
              .having((error) => error.expectedCrc32, 'expectedCrc32', 0)
              .having(
                (error) => error.actualCrc32,
                'actualCrc32',
                0x55bc801d,
              ),
        ),
      );
    });

    test('fails on a short source', () async {
      final future = _collect(
        streamZip([
          StreamingZipEntry(
            name: 'short.mp4',
            sizeBytes: 5,
            open: () => Stream.fromIterable([
              [1],
              [2, 3],
            ]),
          ),
        ]),
      );

      await expectLater(
        future,
        throwsA(
          isA<StreamingZipSizeMismatchException>()
              .having((error) => error.name, 'name', 'short.mp4')
              .having((error) => error.expectedSize, 'expectedSize', 5)
              .having((error) => error.actualSize, 'actualSize', 3),
        ),
      );
    });

    test('fails before forwarding a chunk that makes a source too long',
        () async {
      final emittedChunks = <List<int>>[];
      Object? streamError;
      await streamZip([
        StreamingZipEntry(
          name: 'long.jpg',
          sizeBytes: 2,
          open: () => Stream.fromIterable([
            [1, 2],
            [3],
          ]),
        ),
      ]).forEach(emittedChunks.add).catchError((Object error) {
        streamError = error;
      });

      expect(
        streamError,
        isA<StreamingZipSizeMismatchException>()
            .having((error) => error.expectedSize, 'expectedSize', 2)
            .having((error) => error.actualSize, 'actualSize', 3),
      );
      expect(emittedChunks, hasLength(2));
      expect(emittedChunks.last, [1, 2]);
    });

    test('rejects source values outside the byte range', () async {
      await expectLater(
        _collect(
          streamZip([
            StreamingZipEntry(
              name: 'invalid.bin',
              sizeBytes: 2,
              open: () => Stream.value([0, 256]),
            ),
          ]),
        ),
        throwsA(
          isA<StreamingZipInvalidByteException>()
              .having((error) => error.name, 'name', 'invalid.bin')
              .having((error) => error.chunkIndex, 'chunkIndex', 1)
              .having((error) => error.value, 'value', 256),
        ),
      );
    });

    test('rejects unsafe or non-normalized paths', () async {
      final unsafePaths = <String>[
        '',
        '/absolute.jpg',
        r'C:\camera\photo.jpg',
        r'folder\photo.jpg',
        'folder/../secret.txt',
        './photo.jpg',
        'folder//photo.jpg',
        'folder/',
        'nul\u0000byte.txt',
      ];

      for (final path in unsafePaths) {
        await expectLater(
          _collect(streamZip([_entry(path, const [])])),
          throwsA(
            isA<UnsafeStreamingZipPathException>().having(
              (error) => error.name,
              'name',
              path,
            ),
          ),
          reason: 'Expected "$path" to be rejected.',
        );
      }
    });

    test('rejects duplicate paths before opening any source', () async {
      var openCount = 0;
      StreamingZipEntry duplicate() => StreamingZipEntry(
            name: 'DCIM/photo.jpg',
            sizeBytes: 0,
            open: () {
              openCount++;
              return const Stream.empty();
            },
          );

      await expectLater(
        _collect(streamZip([duplicate(), duplicate()])),
        throwsA(
          isA<DuplicateStreamingZipPathException>().having(
            (error) => error.name,
            'name',
            'DCIM/photo.jpg',
          ),
        ),
      );
      expect(openCount, 0);
    });

    test('rejects a UTF-8 path that cannot fit in a ZIP name field', () async {
      final oversizedName = '${List.filled(32768, '界').join()}.jpg';

      await expectLater(
        _collect(streamZip([_entry(oversizedName, const [])])),
        throwsA(isA<UnsafeStreamingZipPathException>()),
      );
    });

    test('supports an empty archive', () async {
      final bytes = await _collect(streamZip(const []));

      expect(bytes, hasLength(22));
      expect(_uint32(bytes, 0), 0x06054b50);
      expect(ZipDecoder().decodeBytes(bytes), isEmpty);
    });

    test('emits a ZIP64 local header without reading an oversized source',
        () async {
      var opened = false;
      final header = await streamZip([
        StreamingZipEntry(
          name: 'large/video.mp4',
          sizeBytes: zipClassicUint32Max + 1,
          open: () {
            opened = true;
            return const Stream.empty();
          },
        ),
      ]).first;

      expect(opened, isFalse);
      expect(_uint32(header, 0), 0x04034b50);
      expect(_uint16(header, 4), 45);
      expect(_uint32(header, 18), zipClassicUint32Max);
      expect(_uint32(header, 22), zipClassicUint32Max);
      expect(_uint16(header, 28), 20);

      final extraOffset = 30 + utf8.encode('large/video.mp4').length;
      expect(_uint16(header, extraOffset), 0x0001);
      expect(_uint16(header, extraOffset + 2), 16);
      expect(_uint64(header, extraOffset + 4), zipClassicUint32Max + 1);
      expect(_uint64(header, extraOffset + 12), zipClassicUint32Max + 1);
    });
  });

  group('ZIP64 layout metadata', () {
    test('switches entry size fields only after the classic maximum', () {
      final classic = StreamingZipEntryLayout.forValues(
        sizeBytes: zipClassicUint32Max,
        localHeaderOffset: 0,
      );
      final zip64 = StreamingZipEntryLayout.forValues(
        sizeBytes: zipClassicUint32Max + 1,
        localHeaderOffset: 0,
      );

      expect(classic.usesZip64, isFalse);
      expect(classic.localExtraFieldLength, 0);
      expect(classic.centralExtraFieldLength, 0);
      expect(zip64.sizeUsesZip64, isTrue);
      expect(zip64.offsetUsesZip64, isFalse);
      expect(zip64.versionNeeded, 45);
      expect(zip64.localExtraFieldLength, 20);
      expect(zip64.centralExtraFieldLength, 20);
    });

    test('adds only the central ZIP64 offset field for a large offset', () {
      final classic = StreamingZipEntryLayout.forValues(
        sizeBytes: 1,
        localHeaderOffset: zipClassicUint32Max,
      );
      final zip64 = StreamingZipEntryLayout.forValues(
        sizeBytes: 1,
        localHeaderOffset: zipClassicUint32Max + 1,
      );

      expect(classic.usesZip64, isFalse);
      expect(zip64.sizeUsesZip64, isFalse);
      expect(zip64.offsetUsesZip64, isTrue);
      expect(zip64.localExtraFieldLength, 0);
      expect(zip64.centralExtraFieldLength, 12);
    });

    test('orders both ZIP64 sizes before the local-header offset', () {
      final layout = StreamingZipEntryLayout.forValues(
        sizeBytes: zipClassicUint32Max + 1,
        localHeaderOffset: zipClassicUint32Max + 1,
      );

      expect(layout.sizeUsesZip64, isTrue);
      expect(layout.offsetUsesZip64, isTrue);
      expect(layout.localExtraFieldLength, 20);
      expect(layout.centralExtraFieldLength, 28);
    });

    test('switches end records at count, size, and offset boundaries', () {
      StreamingZipArchiveLayout layout({
        int entryCount = 0,
        int size = 0,
        int offset = 0,
        bool containsZip64Entry = false,
      }) =>
          StreamingZipArchiveLayout.forValues(
            entryCount: entryCount,
            centralDirectorySize: size,
            centralDirectoryOffset: offset,
            containsZip64Entry: containsZip64Entry,
          );

      expect(
        layout(
          entryCount: zipClassicEntryCountMax,
          size: zipClassicUint32Max,
          offset: zipClassicUint32Max,
        ).usesZip64EndRecords,
        isFalse,
      );
      expect(
        layout(entryCount: zipClassicEntryCountMax + 1).entryCountUsesZip64,
        isTrue,
      );
      expect(
        layout(size: zipClassicUint32Max + 1).centralDirectorySizeUsesZip64,
        isTrue,
      );
      expect(
        layout(offset: zipClassicUint32Max + 1).centralDirectoryOffsetUsesZip64,
        isTrue,
      );
      expect(
        layout(containsZip64Entry: true).usesZip64EndRecords,
        isTrue,
      );
    });

    test('rejects negative metadata values', () {
      expect(
        () => StreamingZipEntryLayout.forValues(
          sizeBytes: -1,
          localHeaderOffset: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => StreamingZipArchiveLayout.forValues(
          entryCount: -1,
          centralDirectorySize: 0,
          centralDirectoryOffset: 0,
          containsZip64Entry: false,
        ),
        throwsRangeError,
      );
    });
  });
}

StreamingZipEntry _entry(
  String name,
  List<int> bytes, {
  List<List<int>>? chunks,
}) =>
    StreamingZipEntry(
      name: name,
      sizeBytes: bytes.length,
      modifiedTime: DateTime(2026, 7, 12, 20, 30, 10),
      open: () => Stream.fromIterable(chunks ?? [bytes]),
    );

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

int _indexOfSignature(List<int> bytes, int signature) {
  for (var offset = 0; offset <= bytes.length - 4; offset++) {
    if (_uint32(bytes, offset) == signature) {
      return offset;
    }
  }
  throw StateError(
    'Signature 0x${signature.toRadixString(16)} was not found.',
  );
}

int _uint16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32(List<int> bytes, int offset) =>
    _uint16(bytes, offset) | (_uint16(bytes, offset + 2) << 16);

int _uint64(List<int> bytes, int offset) =>
    _uint32(bytes, offset) | (_uint32(bytes, offset + 4) << 32);
