import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Largest value that fits in a classic ZIP 32-bit size or offset field.
const int zipClassicUint32Max = 0xffffffff;

/// Largest value that fits in a classic ZIP 16-bit entry-count field.
const int zipClassicEntryCountMax = 0xffff;

const int _zipVersion20 = 20;
const int _zipVersion45 = 45;
const int _utf8AndDataDescriptorFlags = 0x0808;
const int _storedCompressionMethod = 0;
const int _zip64ExtraFieldId = 0x0001;

/// Opens the bytes for one ZIP entry.
///
/// A fresh stream must be returned each time the callback is invoked. The
/// writer invokes it exactly once during a successful archive write.
typedef StreamingZipEntryOpener = Stream<List<int>> Function();

/// A file included in a streaming ZIP archive.
///
/// [name] must already be a normalized, relative ZIP path using `/` separators.
/// Its UTF-8 representation is written without modification. [sizeBytes] must
/// exactly match the number of bytes emitted by [open].
final class StreamingZipEntry {
  const StreamingZipEntry({
    required this.name,
    required this.sizeBytes,
    required this.open,
    this.modifiedTime,
    this.expectedCrc32,
  });

  final String name;
  final int sizeBytes;
  final DateTime? modifiedTime;
  final StreamingZipEntryOpener open;

  /// Optional checksum used to validate a source whose CRC-32 is known.
  ///
  /// CRC-32 is always calculated and written to the archive, whether or not
  /// this value is supplied.
  final int? expectedCrc32;
}

/// Testable ZIP64 decisions for an individual entry.
///
/// Keeping this calculation independent of the byte stream makes boundary
/// behavior testable without producing multi-gigabyte fixtures.
final class StreamingZipEntryLayout {
  const StreamingZipEntryLayout._({
    required this.sizeUsesZip64,
    required this.offsetUsesZip64,
  });

  factory StreamingZipEntryLayout.forValues({
    required int sizeBytes,
    required int localHeaderOffset,
  }) {
    if (sizeBytes < 0) {
      throw RangeError.value(sizeBytes, 'sizeBytes', 'Must not be negative.');
    }
    if (localHeaderOffset < 0) {
      throw RangeError.value(
        localHeaderOffset,
        'localHeaderOffset',
        'Must not be negative.',
      );
    }

    return StreamingZipEntryLayout._(
      sizeUsesZip64: sizeBytes > zipClassicUint32Max,
      offsetUsesZip64: localHeaderOffset > zipClassicUint32Max,
    );
  }

  final bool sizeUsesZip64;
  final bool offsetUsesZip64;

  bool get usesZip64 => sizeUsesZip64 || offsetUsesZip64;

  int get versionNeeded => usesZip64 ? _zipVersion45 : _zipVersion20;

  int get localExtraFieldLength => sizeUsesZip64 ? 20 : 0;

  int get centralExtraFieldLength {
    if (!usesZip64) {
      return 0;
    }
    return 4 + (sizeUsesZip64 ? 16 : 0) + (offsetUsesZip64 ? 8 : 0);
  }
}

/// Testable ZIP64 decision for the archive end records.
final class StreamingZipArchiveLayout {
  const StreamingZipArchiveLayout._({
    required this.entryCountUsesZip64,
    required this.centralDirectorySizeUsesZip64,
    required this.centralDirectoryOffsetUsesZip64,
    required this.containsZip64Entry,
  });

  factory StreamingZipArchiveLayout.forValues({
    required int entryCount,
    required int centralDirectorySize,
    required int centralDirectoryOffset,
    required bool containsZip64Entry,
  }) {
    if (entryCount < 0) {
      throw RangeError.value(entryCount, 'entryCount', 'Must not be negative.');
    }
    if (centralDirectorySize < 0) {
      throw RangeError.value(
        centralDirectorySize,
        'centralDirectorySize',
        'Must not be negative.',
      );
    }
    if (centralDirectoryOffset < 0) {
      throw RangeError.value(
        centralDirectoryOffset,
        'centralDirectoryOffset',
        'Must not be negative.',
      );
    }

    return StreamingZipArchiveLayout._(
      entryCountUsesZip64: entryCount > zipClassicEntryCountMax,
      centralDirectorySizeUsesZip64: centralDirectorySize > zipClassicUint32Max,
      centralDirectoryOffsetUsesZip64:
          centralDirectoryOffset > zipClassicUint32Max,
      containsZip64Entry: containsZip64Entry,
    );
  }

  final bool entryCountUsesZip64;
  final bool centralDirectorySizeUsesZip64;
  final bool centralDirectoryOffsetUsesZip64;
  final bool containsZip64Entry;

  bool get usesZip64EndRecords =>
      containsZip64Entry ||
      entryCountUsesZip64 ||
      centralDirectorySizeUsesZip64 ||
      centralDirectoryOffsetUsesZip64;
}

/// Writes STORE-only ZIP and ZIP64 archives without buffering file contents.
///
/// Source chunks are checked, copied once to prevent subsequent mutation, and
/// immediately emitted. Memory use is therefore bounded by the largest source
/// chunk plus the central-directory metadata retained for each entry.
final class StreamingZipWriter {
  const StreamingZipWriter();

  /// Validates archive metadata without opening or consuming any source.
  ///
  /// HTTP integrations can call this before committing response headers so a
  /// bad path, duplicate name, size, or expected checksum produces a normal
  /// error response instead of a truncated archive download.
  void validateEntries(Iterable<StreamingZipEntry> entries) {
    _prepareEntries(entries);
  }

  Stream<List<int>> write(Iterable<StreamingZipEntry> entries) async* {
    final preparedEntries = _prepareEntries(entries);
    final completedEntries = <_CompletedEntry>[];
    var outputOffset = 0;

    for (final prepared in preparedEntries) {
      final layout = StreamingZipEntryLayout.forValues(
        sizeBytes: prepared.entry.sizeBytes,
        localHeaderOffset: outputOffset,
      );
      final timestamp = _DosTimestamp.from(prepared.entry.modifiedTime);
      final localHeader = _buildLocalHeader(
        prepared: prepared,
        timestamp: timestamp,
        layout: layout,
      );
      yield localHeader;

      final localHeaderOffset = outputOffset;
      outputOffset += localHeader.length;

      final crc32 = _Crc32();
      var actualSize = 0;
      final source = prepared.entry.open();
      await for (final sourceChunk in source) {
        if (sourceChunk.isEmpty) {
          continue;
        }
        _validateSourceChunk(sourceChunk, prepared.entry.name);

        final nextSize = actualSize + sourceChunk.length;
        if (nextSize > prepared.entry.sizeBytes) {
          throw StreamingZipSizeMismatchException(
            name: prepared.entry.name,
            expectedSize: prepared.entry.sizeBytes,
            actualSize: nextSize,
          );
        }

        final outputChunk = Uint8List.fromList(sourceChunk);
        crc32.add(outputChunk);
        actualSize = nextSize;
        outputOffset += outputChunk.length;
        yield outputChunk;
      }

      if (actualSize != prepared.entry.sizeBytes) {
        throw StreamingZipSizeMismatchException(
          name: prepared.entry.name,
          expectedSize: prepared.entry.sizeBytes,
          actualSize: actualSize,
        );
      }

      final actualCrc32 = crc32.value;
      final expectedCrc32 = prepared.entry.expectedCrc32;
      if (expectedCrc32 != null && actualCrc32 != expectedCrc32) {
        throw StreamingZipCrcMismatchException(
          name: prepared.entry.name,
          expectedCrc32: expectedCrc32,
          actualCrc32: actualCrc32,
        );
      }

      final dataDescriptor = _buildDataDescriptor(
        crc32: actualCrc32,
        sizeBytes: actualSize,
        usesZip64: layout.sizeUsesZip64,
      );
      yield dataDescriptor;
      outputOffset += dataDescriptor.length;

      completedEntries.add(
        _CompletedEntry(
          prepared: prepared,
          timestamp: timestamp,
          layout: layout,
          localHeaderOffset: localHeaderOffset,
          crc32: actualCrc32,
        ),
      );
    }

    final centralDirectoryOffset = outputOffset;
    var containsZip64Entry = false;
    for (final completed in completedEntries) {
      final centralHeader = _buildCentralDirectoryHeader(completed);
      yield centralHeader;
      outputOffset += centralHeader.length;
      containsZip64Entry |= completed.layout.usesZip64;
    }

    final centralDirectorySize = outputOffset - centralDirectoryOffset;
    final archiveLayout = StreamingZipArchiveLayout.forValues(
      entryCount: completedEntries.length,
      centralDirectorySize: centralDirectorySize,
      centralDirectoryOffset: centralDirectoryOffset,
      containsZip64Entry: containsZip64Entry,
    );

    if (archiveLayout.usesZip64EndRecords) {
      final zip64EndOffset = outputOffset;
      final zip64End = _buildZip64EndOfCentralDirectory(
        entryCount: completedEntries.length,
        centralDirectorySize: centralDirectorySize,
        centralDirectoryOffset: centralDirectoryOffset,
      );
      yield zip64End;
      outputOffset += zip64End.length;

      final locator = _buildZip64EndLocator(zip64EndOffset);
      yield locator;
      outputOffset += locator.length;
    }

    yield _buildEndOfCentralDirectory(
      entryCount: completedEntries.length,
      centralDirectorySize: centralDirectorySize,
      centralDirectoryOffset: centralDirectoryOffset,
      archiveLayout: archiveLayout,
    );
  }
}

/// Convenience wrapper around [StreamingZipWriter.write].
Stream<List<int>> streamZip(Iterable<StreamingZipEntry> entries) =>
    const StreamingZipWriter().write(entries);

List<_PreparedEntry> _prepareEntries(Iterable<StreamingZipEntry> entries) {
  final result = <_PreparedEntry>[];
  final names = <String>{};

  for (final entry in entries) {
    _validateEntryPath(entry.name);
    if (!names.add(entry.name)) {
      throw DuplicateStreamingZipPathException(entry.name);
    }
    if (entry.sizeBytes < 0) {
      throw RangeError.value(
        entry.sizeBytes,
        'sizeBytes',
        'ZIP entry size must not be negative.',
      );
    }
    final expectedCrc32 = entry.expectedCrc32;
    if (expectedCrc32 != null &&
        (expectedCrc32 < 0 || expectedCrc32 > zipClassicUint32Max)) {
      throw RangeError.range(
        expectedCrc32,
        0,
        zipClassicUint32Max,
        'expectedCrc32',
      );
    }

    late final Uint8List encodedName;
    try {
      encodedName = Uint8List.fromList(utf8.encode(entry.name));
    } on FormatException catch (error) {
      throw UnsafeStreamingZipPathException(
        entry.name,
        'Path is not valid UTF-8: ${error.message}',
      );
    }
    if (encodedName.length > 0xffff) {
      throw UnsafeStreamingZipPathException(
        entry.name,
        'UTF-8 path exceeds the ZIP limit of 65535 bytes.',
      );
    }
    result.add(_PreparedEntry(entry: entry, encodedName: encodedName));
  }

  return result;
}

void _validateEntryPath(String name) {
  if (name.isEmpty) {
    throw UnsafeStreamingZipPathException(name, 'Path must not be empty.');
  }
  if (name.contains('\u0000')) {
    throw UnsafeStreamingZipPathException(name, 'Path contains a NUL byte.');
  }
  if (name.contains('\\')) {
    throw UnsafeStreamingZipPathException(
      name,
      'Path must use forward-slash separators.',
    );
  }
  if (name.startsWith('/')) {
    throw UnsafeStreamingZipPathException(name, 'Path must be relative.');
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(name)) {
    throw UnsafeStreamingZipPathException(
      name,
      'Path must not contain a Windows drive prefix.',
    );
  }

  final segments = name.split('/');
  if (segments.any((segment) => segment.isEmpty)) {
    throw UnsafeStreamingZipPathException(
      name,
      'Path contains an empty segment.',
    );
  }
  if (segments.any((segment) => segment == '.' || segment == '..')) {
    throw UnsafeStreamingZipPathException(
      name,
      'Path contains a traversal segment.',
    );
  }
}

void _validateSourceChunk(List<int> chunk, String name) {
  for (var index = 0; index < chunk.length; index++) {
    final byte = chunk[index];
    if (byte < 0 || byte > 0xff) {
      throw StreamingZipInvalidByteException(
        name: name,
        chunkIndex: index,
        value: byte,
      );
    }
  }
}

Uint8List _buildLocalHeader({
  required _PreparedEntry prepared,
  required _DosTimestamp timestamp,
  required StreamingZipEntryLayout layout,
}) {
  final extra = _buildLocalZip64Extra(prepared.entry.sizeBytes, layout);
  final writer = _LittleEndianWriter()
    ..uint32(0x04034b50)
    ..uint16(layout.sizeUsesZip64 ? _zipVersion45 : _zipVersion20)
    ..uint16(_utf8AndDataDescriptorFlags)
    ..uint16(_storedCompressionMethod)
    ..uint16(timestamp.time)
    ..uint16(timestamp.date)
    ..uint32(0)
    ..uint32(layout.sizeUsesZip64 ? zipClassicUint32Max : 0)
    ..uint32(layout.sizeUsesZip64 ? zipClassicUint32Max : 0)
    ..uint16(prepared.encodedName.length)
    ..uint16(extra.length)
    ..bytes(prepared.encodedName)
    ..bytes(extra);
  return writer.takeBytes();
}

Uint8List _buildLocalZip64Extra(
  int sizeBytes,
  StreamingZipEntryLayout layout,
) {
  if (!layout.sizeUsesZip64) {
    return Uint8List(0);
  }
  return (_LittleEndianWriter()
        ..uint16(_zip64ExtraFieldId)
        ..uint16(16)
        ..uint64(sizeBytes)
        ..uint64(sizeBytes))
      .takeBytes();
}

Uint8List _buildDataDescriptor({
  required int crc32,
  required int sizeBytes,
  required bool usesZip64,
}) {
  final writer = _LittleEndianWriter()
    ..uint32(0x08074b50)
    ..uint32(crc32);
  if (usesZip64) {
    writer
      ..uint64(sizeBytes)
      ..uint64(sizeBytes);
  } else {
    writer
      ..uint32(sizeBytes)
      ..uint32(sizeBytes);
  }
  return writer.takeBytes();
}

Uint8List _buildCentralDirectoryHeader(_CompletedEntry completed) {
  final extra = _buildCentralZip64Extra(completed);
  final writer = _LittleEndianWriter()
    ..uint32(0x02014b50)
    ..uint16(completed.layout.versionNeeded)
    ..uint16(completed.layout.versionNeeded)
    ..uint16(_utf8AndDataDescriptorFlags)
    ..uint16(_storedCompressionMethod)
    ..uint16(completed.timestamp.time)
    ..uint16(completed.timestamp.date)
    ..uint32(completed.crc32)
    ..uint32(
      completed.layout.sizeUsesZip64
          ? zipClassicUint32Max
          : completed.prepared.entry.sizeBytes,
    )
    ..uint32(
      completed.layout.sizeUsesZip64
          ? zipClassicUint32Max
          : completed.prepared.entry.sizeBytes,
    )
    ..uint16(completed.prepared.encodedName.length)
    ..uint16(extra.length)
    ..uint16(0)
    ..uint16(0)
    ..uint16(0)
    ..uint32(0)
    ..uint32(
      completed.layout.offsetUsesZip64
          ? zipClassicUint32Max
          : completed.localHeaderOffset,
    )
    ..bytes(completed.prepared.encodedName)
    ..bytes(extra);
  return writer.takeBytes();
}

Uint8List _buildCentralZip64Extra(_CompletedEntry completed) {
  final layout = completed.layout;
  if (!layout.usesZip64) {
    return Uint8List(0);
  }

  final data = _LittleEndianWriter();
  if (layout.sizeUsesZip64) {
    data
      ..uint64(completed.prepared.entry.sizeBytes)
      ..uint64(completed.prepared.entry.sizeBytes);
  }
  if (layout.offsetUsesZip64) {
    data.uint64(completed.localHeaderOffset);
  }
  final dataBytes = data.takeBytes();
  return (_LittleEndianWriter()
        ..uint16(_zip64ExtraFieldId)
        ..uint16(dataBytes.length)
        ..bytes(dataBytes))
      .takeBytes();
}

Uint8List _buildZip64EndOfCentralDirectory({
  required int entryCount,
  required int centralDirectorySize,
  required int centralDirectoryOffset,
}) =>
    (_LittleEndianWriter()
          ..uint32(0x06064b50)
          ..uint64(44)
          ..uint16(_zipVersion45)
          ..uint16(_zipVersion45)
          ..uint32(0)
          ..uint32(0)
          ..uint64(entryCount)
          ..uint64(entryCount)
          ..uint64(centralDirectorySize)
          ..uint64(centralDirectoryOffset))
        .takeBytes();

Uint8List _buildZip64EndLocator(int zip64EndOffset) => (_LittleEndianWriter()
      ..uint32(0x07064b50)
      ..uint32(0)
      ..uint64(zip64EndOffset)
      ..uint32(1))
    .takeBytes();

Uint8List _buildEndOfCentralDirectory({
  required int entryCount,
  required int centralDirectorySize,
  required int centralDirectoryOffset,
  required StreamingZipArchiveLayout archiveLayout,
}) =>
    (_LittleEndianWriter()
          ..uint32(0x06054b50)
          ..uint16(0)
          ..uint16(0)
          ..uint16(
            archiveLayout.entryCountUsesZip64
                ? zipClassicEntryCountMax
                : entryCount,
          )
          ..uint16(
            archiveLayout.entryCountUsesZip64
                ? zipClassicEntryCountMax
                : entryCount,
          )
          ..uint32(
            archiveLayout.centralDirectorySizeUsesZip64
                ? zipClassicUint32Max
                : centralDirectorySize,
          )
          ..uint32(
            archiveLayout.centralDirectoryOffsetUsesZip64
                ? zipClassicUint32Max
                : centralDirectoryOffset,
          )
          ..uint16(0))
        .takeBytes();

final class _PreparedEntry {
  const _PreparedEntry({required this.entry, required this.encodedName});

  final StreamingZipEntry entry;
  final Uint8List encodedName;
}

final class _CompletedEntry {
  const _CompletedEntry({
    required this.prepared,
    required this.timestamp,
    required this.layout,
    required this.localHeaderOffset,
    required this.crc32,
  });

  final _PreparedEntry prepared;
  final _DosTimestamp timestamp;
  final StreamingZipEntryLayout layout;
  final int localHeaderOffset;
  final int crc32;
}

final class _DosTimestamp {
  const _DosTimestamp({required this.time, required this.date});

  factory _DosTimestamp.from(DateTime? modifiedTime) {
    final value = modifiedTime ?? DateTime(1980);
    if (value.year < 1980) {
      return const _DosTimestamp(time: 0, date: 0x0021);
    }
    if (value.year > 2107) {
      return const _DosTimestamp(time: 0xbf7d, date: 0xff9f);
    }

    return _DosTimestamp(
      time: (value.hour << 11) | (value.minute << 5) | (value.second ~/ 2),
      date: ((value.year - 1980) << 9) | (value.month << 5) | value.day,
    );
  }

  final int time;
  final int date;
}

final class _Crc32 {
  var _value = zipClassicUint32Max;

  void add(List<int> bytes) {
    for (final byte in bytes) {
      _value = _crc32Table[(_value ^ byte) & 0xff] ^ (_value >> 8);
    }
  }

  int get value => (_value ^ zipClassicUint32Max) & zipClassicUint32Max;
}

final List<int> _crc32Table = List<int>.generate(256, (index) {
  var value = index;
  for (var bit = 0; bit < 8; bit++) {
    value = (value & 1) == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1;
  }
  return value & zipClassicUint32Max;
}, growable: false);

final class _LittleEndianWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void uint16(int value) {
    _builder.add([value & 0xff, (value >> 8) & 0xff]);
  }

  void uint32(int value) {
    _builder.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  void uint64(int value) {
    _builder.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
      (value >> 32) & 0xff,
      (value >> 40) & 0xff,
      (value >> 48) & 0xff,
      (value >> 56) & 0xff,
    ]);
  }

  void bytes(List<int> value) => _builder.add(value);

  Uint8List takeBytes() => _builder.takeBytes();
}

sealed class StreamingZipException implements Exception {
  const StreamingZipException();
}

final class UnsafeStreamingZipPathException extends StreamingZipException {
  const UnsafeStreamingZipPathException(this.name, this.reason);

  final String name;
  final String reason;

  @override
  String toString() => 'Unsafe ZIP path "$name": $reason';
}

final class DuplicateStreamingZipPathException extends StreamingZipException {
  const DuplicateStreamingZipPathException(this.name);

  final String name;

  @override
  String toString() => 'Duplicate ZIP path "$name".';
}

final class StreamingZipSizeMismatchException extends StreamingZipException {
  const StreamingZipSizeMismatchException({
    required this.name,
    required this.expectedSize,
    required this.actualSize,
  });

  final String name;
  final int expectedSize;
  final int actualSize;

  @override
  String toString() =>
      'ZIP source "$name" emitted $actualSize bytes; expected $expectedSize.';
}

final class StreamingZipCrcMismatchException extends StreamingZipException {
  const StreamingZipCrcMismatchException({
    required this.name,
    required this.expectedCrc32,
    required this.actualCrc32,
  });

  final String name;
  final int expectedCrc32;
  final int actualCrc32;

  @override
  String toString() => 'ZIP source "$name" has CRC-32 '
      '0x${actualCrc32.toRadixString(16).padLeft(8, '0')}; expected '
      '0x${expectedCrc32.toRadixString(16).padLeft(8, '0')}.';
}

final class StreamingZipInvalidByteException extends StreamingZipException {
  const StreamingZipInvalidByteException({
    required this.name,
    required this.chunkIndex,
    required this.value,
  });

  final String name;
  final int chunkIndex;
  final int value;

  @override
  String toString() =>
      'ZIP source "$name" emitted non-byte value $value at chunk index '
      '$chunkIndex.';
}
