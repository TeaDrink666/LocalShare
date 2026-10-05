import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/util/native/publish_file.dart';
import 'package:path/path.dart' as p;

/// The result of a file that was completely written, verified, and committed.
final class BackupFileWriteResult {
  const BackupFileWriteResult({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  /// The final path, after the temporary file was atomically renamed.
  final String path;

  /// The number of bytes actually written to disk.
  final int sizeBytes;

  /// The lowercase hexadecimal SHA-256 digest of the written bytes.
  final String sha256;
}

/// Writes backup media to a native file-system inbox safely.
///
/// Bytes are first streamed to a deterministic, dot-prefixed `.part` file in
/// the destination directory. The temporary name contains only a bounded
/// digest, so untrusted batch IDs, media keys, and file names cannot introduce
/// invalid path characters or an excessively long temporary name.
///
/// A successful write is flushed, closed, and verified before a same-directory
/// rename publishes it at [finalPath]. Existing destination entities are never
/// intentionally replaced.
final class BackupFileWriter {
  const BackupFileWriter();

  /// Streams [bytes] to [finalPath], verifies it, and atomically commits it.
  ///
  /// [expectedSha256], when supplied, must contain exactly 64 hexadecimal
  /// characters. Hash comparison is case-insensitive; the result is always
  /// lowercase.
  Future<BackupFileWriteResult> write({
    required String finalPath,
    required Stream<Uint8List> bytes,
    required int expectedSize,
    required String batchId,
    required String mediaKey,
    String? expectedSha256,
    Future<void> Function(int sizeBytes, String sha256)? beforeCommit,
  }) async {
    _validateArguments(
      finalPath: finalPath,
      expectedSize: expectedSize,
      batchId: batchId,
      mediaKey: mediaKey,
      expectedSha256: expectedSha256,
    );

    final normalizedExpectedSha256 = expectedSha256?.toLowerCase();
    final destination = File(finalPath);
    final temporary = File(
      temporaryPathFor(
        finalPath: finalPath,
        batchId: batchId,
        mediaKey: mediaKey,
      ),
    );
    RandomAccessFile? output;

    try {
      await destination.parent.create(recursive: true);
      await _ensureDestinationDoesNotExist(destination);
      await _deleteDeterministicTemporaryFile(temporary);
      await temporary.create(exclusive: true);
      output = await temporary.open(mode: FileMode.writeOnly);

      final digestSink = _SingleDigestSink();
      final hashInput = sha256.startChunkedConversion(digestSink);
      var actualSize = 0;

      await for (final chunk in bytes) {
        if (chunk.isEmpty) {
          continue;
        }
        await output.writeFrom(chunk);
        hashInput.add(chunk);
        actualSize += chunk.length;
      }

      await output.flush();
      await output.close();
      output = null;
      hashInput.close();
      final actualSha256 = digestSink.value.toString();

      if (actualSize != expectedSize) {
        throw BackupFileSizeMismatchException(
          expectedSize: expectedSize,
          actualSize: actualSize,
        );
      }
      if (normalizedExpectedSha256 != null && actualSha256 != normalizedExpectedSha256) {
        throw BackupFileHashMismatchException(
          expectedSha256: normalizedExpectedSha256,
          actualSha256: actualSha256,
        );
      }

      // Persisting a ready-to-commit signature before the rename allows the
      // receiver to distinguish our completed bytes from an unrelated file
      // after a process crash.
      await _ensureDestinationDoesNotExist(destination);
      await beforeCommit?.call(actualSize, actualSha256);

      // Check again immediately before rename. The callback above performs a
      // durable database write and another process may create the destination
      // during that await. File.rename replaces existing files on some
      // platforms, so this final guard is required.
      await _ensureDestinationDoesNotExist(destination);
      final committed = await publishFileWithoutReplacing(temporary, finalPath);

      return BackupFileWriteResult(
        path: committed.path,
        sizeBytes: actualSize,
        sha256: actualSha256,
      );
    } catch (_) {
      final openOutput = output;
      output = null;
      if (openOutput != null) {
        try {
          await openOutput.close();
        } on Object {
          // Preserve the original write/verification failure.
        }
      }
      await _deleteTemporaryFileAfterFailure(temporary);
      rethrow;
    }
  }

  /// Returns the bounded deterministic `.part` path used by [write].
  static String temporaryPathFor({
    required String finalPath,
    required String batchId,
    required String mediaKey,
  }) {
    final identity = jsonEncode(<String>[
      p.basename(finalPath),
      batchId,
      mediaKey,
    ]);
    final digest = sha256.convert(utf8.encode(identity)).toString();
    final temporaryName = '.localshare-backup-${digest.substring(0, 32)}.part';
    return p.join(p.dirname(finalPath), temporaryName);
  }
}

/// Thrown when committing would replace an existing file, link, or directory.
final class BackupFileAlreadyExistsException extends FileSystemException {
  BackupFileAlreadyExistsException(String path) : super('Backup destination already exists', path);
}

/// Thrown when the sender's declared byte length does not match the stream.
final class BackupFileSizeMismatchException implements Exception {
  const BackupFileSizeMismatchException({
    required this.expectedSize,
    required this.actualSize,
  });

  final int expectedSize;
  final int actualSize;

  @override
  String toString() => 'BackupFileSizeMismatchException('
      'expectedSize: $expectedSize, actualSize: $actualSize)';
}

/// Thrown when the sender's SHA-256 does not match the received bytes.
final class BackupFileHashMismatchException implements Exception {
  const BackupFileHashMismatchException({
    required this.expectedSha256,
    required this.actualSha256,
  });

  final String expectedSha256;
  final String actualSha256;

  @override
  String toString() => 'BackupFileHashMismatchException('
      'expectedSha256: $expectedSha256, actualSha256: $actualSha256)';
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final digest = _value;
    if (digest == null) {
      throw StateError('The SHA-256 converter did not produce a digest.');
    }
    return digest;
  }

  @override
  void add(Digest data) {
    if (_value != null) {
      throw StateError('The SHA-256 converter produced multiple digests.');
    }
    _value = data;
  }

  @override
  void close() {
    if (_value == null) {
      throw StateError('The SHA-256 converter produced no digest.');
    }
  }
}

void _validateArguments({
  required String finalPath,
  required int expectedSize,
  required String batchId,
  required String mediaKey,
  required String? expectedSha256,
}) {
  if (finalPath.trim().isEmpty) {
    throw ArgumentError.value(finalPath, 'finalPath', 'Must not be empty');
  }
  if (expectedSize < 0) {
    throw RangeError.value(expectedSize, 'expectedSize', 'Must not be negative');
  }
  if (batchId.trim().isEmpty) {
    throw ArgumentError.value(batchId, 'batchId', 'Must not be empty');
  }
  if (mediaKey.trim().isEmpty) {
    throw ArgumentError.value(mediaKey, 'mediaKey', 'Must not be empty');
  }
  if (expectedSha256 != null && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(expectedSha256)) {
    throw ArgumentError.value(
      expectedSha256,
      'expectedSha256',
      'Must contain exactly 64 hexadecimal characters',
    );
  }
}

Future<void> _ensureDestinationDoesNotExist(File destination) async {
  final type = await FileSystemEntity.type(
    destination.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.notFound) {
    throw BackupFileAlreadyExistsException(destination.path);
  }
}

Future<void> _deleteDeterministicTemporaryFile(File temporary) async {
  final type = await FileSystemEntity.type(
    temporary.path,
    followLinks: false,
  );
  if (type != FileSystemEntityType.notFound) {
    await temporary.delete();
  }
}

Future<void> _deleteTemporaryFileAfterFailure(File temporary) async {
  try {
    final type = await FileSystemEntity.type(
      temporary.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound) {
      await temporary.delete();
    }
  } on Object {
    // Cleanup must not hide the original write/verification exception.
  }
}
