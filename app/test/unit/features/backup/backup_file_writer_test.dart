import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/features/backup/receiver/backup_file_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const writer = BackupFileWriter();
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'localshare-backup-writer-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('streams, flushes, verifies, and commits a file', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(8193, (index) => (index * 31) & 0xff),
    );
    final expectedHash = sha256.convert(payload).toString();
    final finalPath = p.join(temporaryDirectory.path, '相机', '夏天🌻.jpg');

    final result = await writer.write(
      finalPath: finalPath,
      bytes: Stream<Uint8List>.fromIterable([
        Uint8List.sublistView(payload, 0, 3),
        Uint8List(0),
        Uint8List.sublistView(payload, 3, 4097),
        Uint8List.sublistView(payload, 4097),
      ]),
      expectedSize: payload.length,
      expectedSha256: expectedHash.toUpperCase(),
      batchId: '批次：2026/07/13',
      mediaKey: 'external:DCIM/夏天🌻',
    );

    expect(result.path, finalPath);
    expect(result.sizeBytes, payload.length);
    expect(result.sha256, expectedHash);
    expect(await File(finalPath).readAsBytes(), payload);
    expect(
      await File(
        _temporaryPath(
          finalPath,
          batchId: '批次：2026/07/13',
          mediaKey: 'external:DCIM/夏天🌻',
        ),
      ).exists(),
      isFalse,
    );
  });

  test('always calculates and returns SHA-256 when no digest is expected',
      () async {
    final finalPath = p.join(temporaryDirectory.path, 'empty.bin');

    final result = await writer.write(
      finalPath: finalPath,
      bytes: const Stream<Uint8List>.empty(),
      expectedSize: 0,
      batchId: 'batch-empty',
      mediaKey: 'media-empty',
    );

    expect(result.sizeBytes, 0);
    expect(result.sha256, sha256.convert(const <int>[]).toString());
    expect(await File(finalPath).length(), 0);
  });

  test('deletes the part file and publishes nothing on size mismatch',
      () async {
    final finalPath = p.join(temporaryDirectory.path, 'wrong-size.mp4');

    await expectLater(
      writer.write(
        finalPath: finalPath,
        bytes: Stream.value(Uint8List.fromList([1, 2, 3])),
        expectedSize: 4,
        batchId: 'batch-size',
        mediaKey: 'media-size',
      ),
      throwsA(
        isA<BackupFileSizeMismatchException>()
            .having((error) => error.expectedSize, 'expectedSize', 4)
            .having((error) => error.actualSize, 'actualSize', 3),
      ),
    );

    expect(await File(finalPath).exists(), isFalse);
    expect(
      await File(
        _temporaryPath(
          finalPath,
          batchId: 'batch-size',
          mediaKey: 'media-size',
        ),
      ).exists(),
      isFalse,
    );
  });

  test('deletes the part file and publishes nothing on hash mismatch',
      () async {
    final payload = Uint8List.fromList(utf8.encode('received bytes'));
    final finalPath = p.join(temporaryDirectory.path, 'wrong-hash.jpg');
    final actualHash = sha256.convert(payload).toString();

    await expectLater(
      writer.write(
        finalPath: finalPath,
        bytes: Stream.value(payload),
        expectedSize: payload.length,
        expectedSha256: '0' * 64,
        batchId: 'batch-hash',
        mediaKey: 'media-hash',
      ),
      throwsA(
        isA<BackupFileHashMismatchException>()
            .having(
              (error) => error.expectedSha256,
              'expectedSha256',
              '0' * 64,
            )
            .having(
              (error) => error.actualSha256,
              'actualSha256',
              actualHash,
            ),
      ),
    );

    expect(await File(finalPath).exists(), isFalse);
    expect(
      await File(
        _temporaryPath(
          finalPath,
          batchId: 'batch-hash',
          mediaKey: 'media-hash',
        ),
      ).exists(),
      isFalse,
    );
  });

  test('cleans up after a source stream error', () async {
    final finalPath = p.join(temporaryDirectory.path, 'stream-error.mp4');

    await expectLater(
      writer.write(
        finalPath: finalPath,
        bytes: _failingStream(),
        expectedSize: 3,
        batchId: 'batch-stream',
        mediaKey: 'media-stream',
      ),
      throwsStateError,
    );

    expect(await File(finalPath).exists(), isFalse);
    expect(
      await File(
        _temporaryPath(
          finalPath,
          batchId: 'batch-stream',
          mediaKey: 'media-stream',
        ),
      ).exists(),
      isFalse,
    );
  });

  test('removes only its deterministic stale part before writing', () async {
    final finalPath = p.join(temporaryDirectory.path, 'retry.jpg');
    final stalePart = File(
      _temporaryPath(
        finalPath,
        batchId: 'batch-test',
        mediaKey: 'media-test',
      ),
    );
    final unrelatedPart = File(p.join(temporaryDirectory.path, 'keep.part'));
    await stalePart.writeAsString('incomplete previous attempt');
    await unrelatedPart.writeAsString('unrelated data');

    await writer.write(
      finalPath: finalPath,
      bytes: Stream.value(Uint8List.fromList([7, 8, 9])),
      expectedSize: 3,
      batchId: 'batch-test',
      mediaKey: 'media-test',
    );

    expect(await File(finalPath).readAsBytes(), [7, 8, 9]);
    expect(await stalePart.exists(), isFalse);
    expect(await unrelatedPart.readAsString(), 'unrelated data');
  });

  test('refuses to overwrite an existing destination', () async {
    final finalPath = p.join(temporaryDirectory.path, 'existing.jpg');
    final destination = File(finalPath);
    await destination.writeAsString('original');
    var sourceWasListenedTo = false;
    final source = Stream<Uint8List>.multi((controller) {
      sourceWasListenedTo = true;
      controller.add(Uint8List.fromList([1, 2, 3]));
      controller.close();
    });

    await expectLater(
      writer.write(
        finalPath: finalPath,
        bytes: source,
        expectedSize: 3,
        batchId: 'batch-test',
        mediaKey: 'media-test',
      ),
      throwsA(isA<BackupFileAlreadyExistsException>()),
    );

    expect(sourceWasListenedTo, isFalse);
    expect(await destination.readAsString(), 'original');
    expect(
      await File(
        _temporaryPath(
          finalPath,
          batchId: 'batch-test',
          mediaKey: 'media-test',
        ),
      ).exists(),
      isFalse,
    );
  });

  test('does not replace a destination created while bytes are arriving',
      () async {
    final finalPath = p.join(temporaryDirectory.path, 'raced.jpg');
    final destination = File(finalPath);

    Stream<Uint8List> source() async* {
      yield Uint8List.fromList([1, 2, 3]);
      await destination.writeAsString('created by another writer');
    }

    await expectLater(
      writer.write(
        finalPath: finalPath,
        bytes: source(),
        expectedSize: 3,
        batchId: 'batch-race',
        mediaKey: 'media-race',
      ),
      throwsA(isA<BackupFileAlreadyExistsException>()),
    );

    expect(await destination.readAsString(), 'created by another writer');
    expect(
      await File(
        _temporaryPath(
          finalPath,
          batchId: 'batch-race',
          mediaKey: 'media-race',
        ),
      ).exists(),
      isFalse,
    );
  });

  test('uses a same-directory bounded digest for unsafe long identifiers', () {
    final finalPath = p.join(temporaryDirectory.path, 'photo.jpg');
    final tempPath = BackupFileWriter.temporaryPathFor(
      finalPath: finalPath,
      batchId: r'batch<>:"/\|?*' * 100,
      mediaKey: '媒体🌻/../CON' * 100,
    );

    expect(p.dirname(tempPath), p.dirname(finalPath));
    expect(
      p.basename(tempPath),
      matches(RegExp(r'^\.localshare-backup-[0-9a-f]{32}\.part$')),
    );
    expect(p.basename(tempPath).length, lessThan(64));
    expect(tempPath, isNot(contains('CON')));
    expect(
      tempPath,
      BackupFileWriter.temporaryPathFor(
        finalPath: finalPath,
        batchId: r'batch<>:"/\|?*' * 100,
        mediaKey: '媒体🌻/../CON' * 100,
      ),
    );
  });
}

String _temporaryPath(
  String finalPath, {
  required String batchId,
  required String mediaKey,
}) {
  return BackupFileWriter.temporaryPathFor(
    finalPath: finalPath,
    batchId: batchId,
    mediaKey: mediaKey,
  );
}

Stream<Uint8List> _failingStream() async* {
  yield Uint8List.fromList([1, 2]);
  throw StateError('source failed');
}
