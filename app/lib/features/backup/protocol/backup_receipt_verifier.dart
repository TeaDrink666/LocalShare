import 'dart:collection';

import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/protocol/backup_manifest_digest.dart';
import 'package:localsend_app/features/backup/protocol/backup_protocol_models.dart';

/// Verifies that receiver claims describe the exact current phone manifest.
///
/// No media key is returned until the response reference and every persisted
/// item signature match. Callers may safely pass the result to partial pending
/// confirmation.
final class BackupReceiptVerifier {
  const BackupReceiptVerifier({
    this.digester = const BackupManifestDigest(),
  });

  final BackupManifestDigest digester;

  /// Validates a plan and returns the items already confirmed by the receiver.
  ///
  /// A plan must partition the entire current manifest into required and
  /// already committed items, with neither overlap nor omissions.
  Set<String> verifyPlan({
    required BackupManifest currentManifest,
    required String expectedTargetFingerprint,
    required BackupPlanResponse response,
  }) {
    final committed = verifyCommittedItems(
      currentManifest: currentManifest,
      expectedTargetFingerprint: expectedTargetFingerprint,
      response: response,
    );
    final manifestKeys = _manifestByKey(currentManifest).keys.toSet();
    final required = response.requiredMediaKeys.toSet();
    final unknownRequired = required.difference(manifestKeys);
    if (unknownRequired.isNotEmpty) {
      throw BackupProtocolVerificationException(
        'Plan requires unknown media keys: ${_sorted(unknownRequired).join(', ')}',
      );
    }
    final overlap = required.intersection(committed);
    if (overlap.isNotEmpty) {
      throw BackupProtocolVerificationException(
        'Plan marks media keys as both required and committed: '
        '${_sorted(overlap).join(', ')}',
      );
    }
    final covered = {...required, ...committed};
    final omitted = manifestKeys.difference(covered);
    if (omitted.isNotEmpty) {
      throw BackupProtocolVerificationException(
        'Plan omits media keys: ${_sorted(omitted).join(', ')}',
      );
    }
    return committed;
  }

  /// Validates a commit or recovered receipt and returns only trusted keys.
  Set<String> verifyCommittedItems({
    required BackupManifest currentManifest,
    required String expectedTargetFingerprint,
    required BackupCommittedItemsResponse response,
  }) {
    final reference = response.reference;
    _expectEqual('batchId', reference.batchId, currentManifest.batchId);
    _expectEqual('profileId', reference.profileId, currentManifest.profileId);
    _expectEqual(
      'sourceDevice',
      reference.sourceDevice,
      currentManifest.sourceDevice,
    );
    _expectEqual(
      'targetFingerprint',
      reference.targetFingerprint,
      expectedTargetFingerprint,
    );
    _expectEqual(
      'manifestSha256',
      reference.manifestSha256,
      digester.calculate(currentManifest),
    );

    final manifestByKey = _manifestByKey(currentManifest);
    final trusted = <String>{};
    for (final committed in response.committedItems) {
      final expected = manifestByKey[committed.mediaKey];
      if (expected == null) {
        throw BackupProtocolVerificationException(
          'Committed item is not in the current manifest: '
          '${committed.mediaKey}',
        );
      }
      if (!trusted.add(committed.mediaKey)) {
        throw BackupProtocolVerificationException(
          'Duplicate committed media key: ${committed.mediaKey}',
        );
      }

      final media = expected.snapshotItem;
      _expectItemEqual(
        committed.mediaKey,
        'relativePath',
        committed.relativePath,
        media.relativePath,
      );
      _expectItemEqual(
        committed.mediaKey,
        'displayName',
        committed.displayName,
        media.displayName,
      );
      _expectItemEqual(
        committed.mediaKey,
        'sizeBytes',
        committed.sizeBytes,
        media.sizeBytes,
      );
      _expectItemEqual(
        committed.mediaKey,
        'modifiedAtSeconds',
        committed.modifiedAtSeconds,
        media.modifiedAtSeconds,
      );
      _expectItemEqual(
        committed.mediaKey,
        'generationModified',
        committed.generationModified,
        media.generationModified,
      );
      _expectItemEqual(
        committed.mediaKey,
        'sha256',
        committed.sha256,
        expected.sha256,
      );
    }

    return UnmodifiableSetView(trusted);
  }
}

/// A protocol-valid response that cannot be trusted for the current manifest.
final class BackupProtocolVerificationException extends FormatException {
  BackupProtocolVerificationException(super.message);
}

Map<String, BackupManifestItem> _manifestByKey(BackupManifest manifest) {
  return <String, BackupManifestItem>{
    for (final item in manifest.items) item.snapshotItem.mediaKey: item,
  };
}

void _expectEqual(String field, Object? actual, Object? expected) {
  if (actual != expected) {
    throw BackupProtocolVerificationException(
      'Receipt $field does not match the current manifest: '
      '$actual != $expected',
    );
  }
}

void _expectItemEqual(
  String mediaKey,
  String field,
  Object? actual,
  Object? expected,
) {
  if (actual != expected) {
    throw BackupProtocolVerificationException(
      'Committed item $mediaKey has mismatched $field: '
      '$actual != $expected',
    );
  }
}

List<String> _sorted(Iterable<String> values) {
  return values.toList()..sort();
}
