import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/manifest.dart';
import 'package:localsend_app/features/backup/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  const manifestCodec = BackupManifestCodec();
  const protocolCodec = BackupProtocolCodec();
  const digester = BackupManifestDigest();
  const verifier = BackupReceiptVerifier();

  group('BackupProtocolRoutes', () {
    test('keeps every endpoint below the versioned backup namespace', () {
      expect(BackupProtocolRoutes.plan, '/api/localshare/backup/v1/plan');
      expect(BackupProtocolRoutes.commit, '/api/localshare/backup/v1/commit');
      expect(BackupProtocolRoutes.receipt, '/api/localshare/backup/v1/receipt');
      expect(BackupProtocolRoutes.cancel, '/api/localshare/backup/v1/cancel');
      expect(localShareBackupMetadataField, 'localShareBackup');
    });
  });

  group('canonical manifest digest', () {
    test('hashes the exact canonical UTF-8 manifest JSON', () {
      final manifest = _manifest();
      final canonicalJson = manifestCodec.encode(manifest);
      final independentlyCalculated =
          sha256.convert(utf8.encode(canonicalJson)).toString();

      expect(digester.calculate(manifest), independentlyCalculated);
      expect(
        digester.calculate(
          BackupManifest(
            batchId: manifest.batchId,
            profileId: manifest.profileId,
            sourceDevice: manifest.sourceDevice,
            createdAtUtc: manifest.createdAtUtc,
            items: manifest.items.reversed,
          ),
        ),
        independentlyCalculated,
      );
    });

    test('changes when a pending retry uses a smaller manifest', () {
      final full = _manifest();
      final remaining = _manifest(items: [full.items.last]);

      expect(remaining.batchId, full.batchId);
      expect(digester.calculate(remaining), isNot(digester.calculate(full)));
    });
  });

  group('prepare metadata', () {
    test('attaches and strictly decodes namespaced request metadata', () {
      final metadata = _metadata();
      final request = protocolCodec.attachPrepareMetadata(
        <String, Object?>{
          'info': <String, Object?>{'alias': '手机'},
          'files': <String, Object?>{},
        },
        metadata,
      );
      final decoded = protocolCodec.prepareMetadataFromRequestJson(request);

      expect(request.keys, contains(localShareBackupMetadataField));
      expect(decoded.targetFingerprint, 'windows-fingerprint');
      expect(decoded.manifestSha256, digester.calculate(decoded.manifest));
      expect(decoded.fileIdToMediaKey, {
        'file-1': 'external:1',
        'file-2': 'external:2',
      });
      expect(() => decoded.fileIdToMediaKey.clear(), throwsUnsupportedError);
    });

    test('requires an exact one-to-one file mapping', () {
      final manifest = _manifest();

      expect(
        () => BackupPrepareMetadata(
          manifest: manifest,
          fileIdToMediaKey: const {'file-1': 'external:1'},
          targetFingerprint: 'windows-fingerprint',
        ),
        throwsArgumentError,
      );
      expect(
        () => BackupPrepareMetadata(
          manifest: manifest,
          fileIdToMediaKey: const {
            'file-1': 'external:1',
            'file-2': 'external:1',
          },
          targetFingerprint: 'windows-fingerprint',
        ),
        throwsArgumentError,
      );
      expect(
        () => BackupPrepareMetadata(
          manifest: manifest,
          fileIdToMediaKey: const {
            'file-1': 'external:1',
            'file-2': 'external:unknown',
          },
          targetFingerprint: 'windows-fingerprint',
        ),
        throwsArgumentError,
      );
    });

    test('rejects a forged digest and unknown metadata fields', () {
      final document = protocolCodec.prepareMetadataToJson(_metadata());
      final forged = Map<String, Object?>.from(document)
        ..['manifestSha256'] = 'f' * 64;
      final extended = Map<String, Object?>.from(document)..['extra'] = true;

      expect(
        () => protocolCodec.prepareMetadataFromJson(forged),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => protocolCodec.prepareMetadataFromJson(extended),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => protocolCodec.prepareMetadataFromRequestJson(
          const <String, Object?>{'files': <String, Object?>{}},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('protocol request and response codec', () {
    test('round trips plan request and response', () {
      final request = BackupPlanRequest(metadata: _metadata());
      final response = BackupPlanResponse(
        reference: request.metadata.reference,
        requiredMediaKeys: const ['external:2'],
        committedItems: [_committed(request.metadata.manifest.items.first)],
      );

      final decodedRequest = protocolCodec.decodePlanRequest(
        protocolCodec.encodePlanRequest(request),
      );
      final decodedResponse = protocolCodec.decodePlanResponse(
        protocolCodec.encodePlanResponse(response),
      );

      expect(decodedRequest.metadata.manifest.itemCount, 2);
      expect(decodedRequest.metadata.fileIdToMediaKey['file-2'], 'external:2');
      expect(decodedResponse.requiredMediaKeys, ['external:2']);
      expect(decodedResponse.committedItems.single.mediaKey, 'external:1');
    });

    test('round trips commit, receipt, and cancel messages', () {
      final metadata = _metadata();
      final reference = metadata.reference;
      final committedItems = [
        for (final item in metadata.manifest.items) _committed(item),
      ];

      final commitRequest = protocolCodec.decodeCommitRequest(
        protocolCodec.encodeCommitRequest(
          BackupCommitRequest(metadata: metadata.manifestMetadata),
        ),
      );
      final commitResponse = protocolCodec.decodeCommitResponse(
        protocolCodec.encodeCommitResponse(
          BackupCommitResponse(
            reference: reference,
            committedItems: committedItems,
          ),
        ),
      );
      final receiptRequest = protocolCodec.decodeReceiptRequest(
        protocolCodec.encodeReceiptRequest(
          BackupReceiptRequest(metadata: metadata.manifestMetadata),
        ),
      );
      final receiptResponse = protocolCodec.decodeReceiptResponse(
        protocolCodec.encodeReceiptResponse(
          BackupReceiptResponse(
            reference: reference,
            committedItems: committedItems,
          ),
        ),
      );
      final cancelResponse = protocolCodec.decodeCancelResponse(
        protocolCodec.encodeCancelResponse(
          BackupCancelResponse(
            reference: protocolCodec
                .decodeCancelRequest(
                  protocolCodec.encodeCancelRequest(
                    BackupCancelRequest(reference: reference),
                  ),
                )
                .reference,
            canceledAtUtc: DateTime.utc(2026, 7, 13, 12),
          ),
        ),
      );

      expect(
        commitRequest.metadata.manifest.batchId,
        metadata.manifest.batchId,
      );
      expect(commitResponse.committedItems, hasLength(2));
      expect(
        receiptRequest.metadata.manifestSha256,
        metadata.manifestSha256,
      );
      expect(receiptResponse.committedItems.last.mediaKey, 'external:2');
      expect(cancelResponse.canceledAtUtc, DateTime.utc(2026, 7, 13, 12));
    });

    test('rejects unsupported versions and unexpected fields', () {
      final response = BackupReceiptResponse(
        reference: _metadata().reference,
        committedItems: const [],
      );
      final wrongVersion = protocolCodec.receiptResponseToJson(response)
        ..['protocolVersion'] = 2;
      final unexpected = protocolCodec.receiptResponseToJson(response)
        ..['trusted'] = true;

      expect(
        () => protocolCodec.receiptResponseFromJson(wrongVersion),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => protocolCodec.receiptResponseFromJson(unexpected),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate committed keys and non-UTC verification time', () {
      final metadata = _metadata();
      final item = _committed(metadata.manifest.items.first);
      final duplicate = protocolCodec.receiptResponseToJson(
        BackupReceiptResponse(
          reference: metadata.reference,
          committedItems: [item],
        ),
      );
      duplicate['committedItems'] = [
        ...(duplicate['committedItems']! as List<Object?>),
        ...(duplicate['committedItems']! as List<Object?>),
      ];
      final localTime = protocolCodec.receiptResponseToJson(
        BackupReceiptResponse(
          reference: metadata.reference,
          committedItems: [item],
        ),
      );
      ((localTime['committedItems']! as List).single as Map)['verifiedAtUtc'] =
          '2026-07-13T12:00:00+08:00';

      expect(
        () => protocolCodec.receiptResponseFromJson(duplicate),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => protocolCodec.receiptResponseFromJson(localTime),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('trusted committed media keys', () {
    test('accepts an exact plan partition and exact partial receipt', () {
      final metadata = _metadata();
      final first = metadata.manifest.items.first;
      final second = metadata.manifest.items.last;
      final plan = BackupPlanResponse(
        reference: metadata.reference,
        requiredMediaKeys: [second.snapshotItem.mediaKey],
        committedItems: [_committed(first)],
      );
      final receipt = BackupReceiptResponse(
        reference: metadata.reference,
        committedItems: [_committed(second)],
      );

      expect(
        verifier.verifyPlan(
          currentManifest: metadata.manifest,
          expectedTargetFingerprint: metadata.targetFingerprint,
          response: plan,
        ),
        {'external:1'},
      );
      final trusted = verifier.verifyCommittedItems(
        currentManifest: metadata.manifest,
        expectedTargetFingerprint: metadata.targetFingerprint,
        response: receipt,
      );
      expect(trusted, {'external:2'});
      expect(() => trusted.add('forged'), throwsUnsupportedError);
    });

    test('accepts the same batch with the digest of a remaining subset', () {
      final original = _manifest();
      final remaining = _manifest(items: [original.items.last]);
      final reference = _referenceFor(remaining);
      final response = BackupReceiptResponse(
        reference: reference,
        committedItems: [_committed(remaining.items.single)],
      );

      expect(reference.batchId, original.batchId);
      expect(
        reference.manifestSha256,
        isNot(digester.calculate(original)),
      );
      expect(
        verifier.verifyCommittedItems(
          currentManifest: remaining,
          expectedTargetFingerprint: 'windows-fingerprint',
          response: response,
        ),
        {'external:2'},
      );
    });

    test('rejects a wrong response identity or manifest digest', () {
      final metadata = _metadata();
      final committed = [_committed(metadata.manifest.items.first)];
      for (final reference in [
        _referenceFor(metadata.manifest, batchId: 'other-batch'),
        _referenceFor(metadata.manifest, profileId: 'other-profile'),
        _referenceFor(metadata.manifest, sourceDevice: 'other-phone'),
        _referenceFor(metadata.manifest, targetFingerprint: 'other-pc'),
        _referenceFor(metadata.manifest, manifestSha256: 'f' * 64),
      ]) {
        expect(
          () => verifier.verifyCommittedItems(
            currentManifest: metadata.manifest,
            expectedTargetFingerprint: metadata.targetFingerprint,
            response: BackupReceiptResponse(
              reference: reference,
              committedItems: committed,
            ),
          ),
          throwsA(isA<BackupProtocolVerificationException>()),
        );
      }
    });

    test('rejects every mismatched committed item signature field', () {
      final metadata = _metadata();
      final expected = metadata.manifest.items.first;
      final variants = <BackupCommittedItem>[
        _committed(expected, mediaKey: 'external:unknown'),
        _committed(expected, relativePath: 'Pictures/'),
        _committed(expected, displayName: 'renamed.jpg'),
        _committed(expected, sizeBytes: expected.snapshotItem.sizeBytes + 1),
        _committed(
          expected,
          modifiedAtSeconds: expected.snapshotItem.modifiedAtSeconds + 1,
        ),
        _committed(
          expected,
          generationModified: expected.snapshotItem.generationModified! + 1,
        ),
        _committed(expected, sha256: 'c' * 64),
      ];

      for (final variant in variants) {
        expect(
          () => verifier.verifyCommittedItems(
            currentManifest: metadata.manifest,
            expectedTargetFingerprint: metadata.targetFingerprint,
            response: BackupReceiptResponse(
              reference: metadata.reference,
              committedItems: [variant],
            ),
          ),
          throwsA(isA<BackupProtocolVerificationException>()),
          reason:
              'Expected ${variant.mediaKey}/${variant.displayName} rejection',
        );
      }
    });

    test('rejects plan overlap, omission, and unknown required keys', () {
      final metadata = _metadata();
      final first = metadata.manifest.items.first;

      for (final required in [
        const ['external:1', 'external:2'],
        const <String>[],
        const ['external:2', 'external:unknown'],
      ]) {
        expect(
          () => verifier.verifyPlan(
            currentManifest: metadata.manifest,
            expectedTargetFingerprint: metadata.targetFingerprint,
            response: BackupPlanResponse(
              reference: metadata.reference,
              requiredMediaKeys: required,
              committedItems: [_committed(first)],
            ),
          ),
          throwsA(isA<BackupProtocolVerificationException>()),
        );
      }
    });
  });
}

BackupPrepareMetadata _metadata() {
  return BackupPrepareMetadata(
    manifest: _manifest(),
    fileIdToMediaKey: const {
      'file-2': 'external:2',
      'file-1': 'external:1',
    },
    targetFingerprint: 'windows-fingerprint',
  );
}

BackupManifest _manifest({Iterable<BackupManifestItem>? items}) {
  return BackupManifest(
    batchId: 'batch-2026-07-13',
    profileId: 'home-pc',
    sourceDevice: 'android-phone',
    createdAtUtc: DateTime.utc(2026, 7, 13, 8, 30),
    items: items ??
        [
          _item(
            key: 'external:1',
            path: 'DCIM/Camera/',
            name: 'IMG_0001.jpg',
            size: 100,
            modified: 1700000001,
            generation: 7,
            sha256: 'a' * 64,
          ),
          _item(
            key: 'external:2',
            path: 'Movies/',
            name: 'VID_0002.mp4',
            size: 800,
            modified: 1700000002,
            generation: null,
            sha256: 'b' * 64,
          ),
        ],
  );
}

BackupManifestItem _item({
  required String key,
  required String path,
  required String name,
  required int size,
  required int modified,
  required int? generation,
  required String? sha256,
}) {
  return BackupManifestItem(
    snapshotItem: MediaSnapshotItem(
      mediaKey: key,
      relativePath: path,
      displayName: name,
      sizeBytes: size,
      modifiedAtSeconds: modified,
      generationModified: generation,
      mimeType: name.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg',
    ),
    sha256: sha256,
  );
}

BackupBatchReference _referenceFor(
  BackupManifest manifest, {
  String? batchId,
  String? profileId,
  String? sourceDevice,
  String? targetFingerprint,
  String? manifestSha256,
}) {
  return BackupBatchReference(
    batchId: batchId ?? manifest.batchId,
    profileId: profileId ?? manifest.profileId,
    sourceDevice: sourceDevice ?? manifest.sourceDevice,
    targetFingerprint: targetFingerprint ?? 'windows-fingerprint',
    manifestSha256:
        manifestSha256 ?? const BackupManifestDigest().calculate(manifest),
  );
}

BackupCommittedItem _committed(
  BackupManifestItem item, {
  String? mediaKey,
  String? relativePath,
  String? displayName,
  int? sizeBytes,
  int? modifiedAtSeconds,
  int? generationModified,
  String? sha256,
}) {
  final media = item.snapshotItem;
  return BackupCommittedItem(
    mediaKey: mediaKey ?? media.mediaKey,
    relativePath: relativePath ?? media.relativePath,
    displayName: displayName ?? media.displayName,
    sizeBytes: sizeBytes ?? media.sizeBytes,
    modifiedAtSeconds: modifiedAtSeconds ?? media.modifiedAtSeconds,
    generationModified: generationModified ?? media.generationModified,
    sha256: sha256 ?? item.sha256,
    verifiedAtUtc: DateTime.utc(2026, 7, 13, 9),
  );
}
