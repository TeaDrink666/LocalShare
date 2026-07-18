import 'dart:collection';

import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/protocol/backup_manifest_digest.dart';
import 'package:localsend_app/features/backup/protocol/backup_protocol_routes.dart';

/// The exact current manifest and destination used to query persisted proofs.
final class BackupManifestMetadata {
  BackupManifestMetadata({
    required this.manifest,
    required this.targetFingerprint,
    String? manifestSha256,
    BackupManifestDigest digester = const BackupManifestDigest(),
  }) : manifestSha256 = manifestSha256 ?? digester.calculate(manifest) {
    _validateManifestIdentity(
      manifest: manifest,
      targetFingerprint: targetFingerprint,
      manifestSha256: this.manifestSha256,
      digester: digester,
    );
  }

  final int protocolVersion = backupProtocolVersion;
  final BackupManifest manifest;
  final String manifestSha256;
  final String targetFingerprint;

  BackupBatchReference get reference => BackupBatchReference(
        batchId: manifest.batchId,
        profileId: manifest.profileId,
        sourceDevice: manifest.sourceDevice,
        targetFingerprint: targetFingerprint,
        manifestSha256: manifestSha256,
      );
}

/// Metadata attached to a normal prepare-upload request.
///
/// The file mapping binds LocalSend's ephemeral file IDs to stable Android
/// media keys. It must cover the current manifest exactly and one-to-one.
final class BackupPrepareMetadata {
  BackupPrepareMetadata({
    required this.manifest,
    required Map<String, String> fileIdToMediaKey,
    required this.targetFingerprint,
    String? manifestSha256,
    BackupManifestDigest digester = const BackupManifestDigest(),
  })  : manifestSha256 = manifestSha256 ?? digester.calculate(manifest),
        fileIdToMediaKey = _freezeFileMapping(
          fileIdToMediaKey,
          manifest,
        ) {
    _validateManifestIdentity(
      manifest: manifest,
      targetFingerprint: targetFingerprint,
      manifestSha256: this.manifestSha256,
      digester: digester,
    );
  }

  final int protocolVersion = backupProtocolVersion;
  final BackupManifest manifest;
  final String manifestSha256;
  final Map<String, String> fileIdToMediaKey;
  final String targetFingerprint;

  BackupManifestMetadata get manifestMetadata => BackupManifestMetadata(
        manifest: manifest,
        targetFingerprint: targetFingerprint,
        manifestSha256: manifestSha256,
      );

  BackupBatchReference get reference => BackupBatchReference(
        batchId: manifest.batchId,
        profileId: manifest.profileId,
        sourceDevice: manifest.sourceDevice,
        targetFingerprint: targetFingerprint,
        manifestSha256: manifestSha256,
      );
}

/// Identifies one attempt against the current canonical manifest.
///
/// A retry may keep [batchId] while using a smaller pending manifest and thus
/// a different [manifestSha256]. Receivers should persist item signatures, not
/// assume that a batch ID permanently identifies one full manifest document.
final class BackupBatchReference {
  BackupBatchReference({
    required this.batchId,
    required this.profileId,
    required this.sourceDevice,
    required this.targetFingerprint,
    required this.manifestSha256,
  }) {
    _validateIdentifier(batchId, 'batchId');
    _validateIdentifier(profileId, 'profileId');
    _validateIdentifier(sourceDevice, 'sourceDevice');
    _validateIdentifier(targetFingerprint, 'targetFingerprint');
    _validateSha256(manifestSha256, 'manifestSha256');
  }

  factory BackupBatchReference.fromMetadata(BackupPrepareMetadata metadata) {
    return metadata.reference;
  }

  final String batchId;
  final String profileId;
  final String sourceDevice;
  final String targetFingerprint;
  final String manifestSha256;
}

/// Receiver-side proof for one fully persisted file.
final class BackupCommittedItem {
  BackupCommittedItem({
    required this.mediaKey,
    required this.relativePath,
    required this.displayName,
    required this.sizeBytes,
    required this.modifiedAtSeconds,
    required this.generationModified,
    required this.sha256,
    required this.verifiedAtUtc,
  }) {
    _validateIdentifier(mediaKey, 'mediaKey');
    _validateRelativePath(relativePath);
    _validateDisplayName(displayName);
    _validateNonNegative(sizeBytes, 'sizeBytes');
    _validateNonNegative(modifiedAtSeconds, 'modifiedAtSeconds');
    final generation = generationModified;
    if (generation != null) {
      _validateNonNegative(generation, 'generationModified');
    }
    final digest = sha256;
    if (digest != null) {
      _validateSha256(digest, 'sha256');
    }
    _validateUtc(verifiedAtUtc, 'verifiedAtUtc');
  }

  final String mediaKey;
  final String relativePath;
  final String displayName;
  final int sizeBytes;
  final int modifiedAtSeconds;
  final int? generationModified;
  final String? sha256;
  final DateTime verifiedAtUtc;
}

final class BackupPlanRequest {
  BackupPlanRequest({required this.metadata});

  final int protocolVersion = backupProtocolVersion;
  final BackupPrepareMetadata metadata;
}

/// The receiver's verified view before uploading the missing items.
final class BackupPlanResponse implements BackupCommittedItemsResponse {
  BackupPlanResponse({
    required this.reference,
    required Iterable<String> requiredMediaKeys,
    required Iterable<BackupCommittedItem> committedItems,
  })  : requiredMediaKeys = _freezeIdentifiers(
          requiredMediaKeys,
          'requiredMediaKeys',
        ),
        committedItems = _freezeCommittedItems(committedItems);

  final int protocolVersion = backupProtocolVersion;
  @override
  final BackupBatchReference reference;
  final List<String> requiredMediaKeys;
  @override
  final List<BackupCommittedItem> committedItems;
}

final class BackupCommitRequest {
  BackupCommitRequest({required this.metadata});

  final int protocolVersion = backupProtocolVersion;
  final BackupManifestMetadata metadata;
}

final class BackupCommitResponse implements BackupCommittedItemsResponse {
  BackupCommitResponse({
    required this.reference,
    required Iterable<BackupCommittedItem> committedItems,
  }) : committedItems = _freezeCommittedItems(committedItems);

  final int protocolVersion = backupProtocolVersion;
  @override
  final BackupBatchReference reference;
  @override
  final List<BackupCommittedItem> committedItems;
}

final class BackupReceiptRequest {
  BackupReceiptRequest({required this.metadata});

  final int protocolVersion = backupProtocolVersion;
  final BackupManifestMetadata metadata;
}

final class BackupReceiptResponse implements BackupCommittedItemsResponse {
  BackupReceiptResponse({
    required this.reference,
    required Iterable<BackupCommittedItem> committedItems,
  }) : committedItems = _freezeCommittedItems(committedItems);

  final int protocolVersion = backupProtocolVersion;
  @override
  final BackupBatchReference reference;
  @override
  final List<BackupCommittedItem> committedItems;
}

final class BackupCancelRequest {
  BackupCancelRequest({required this.reference});

  final int protocolVersion = backupProtocolVersion;
  final BackupBatchReference reference;
}

final class BackupCancelResponse {
  BackupCancelResponse({
    required this.reference,
    required this.canceledAtUtc,
  }) {
    _validateUtc(canceledAtUtc, 'canceledAtUtc');
  }

  final int protocolVersion = backupProtocolVersion;
  final BackupBatchReference reference;
  final DateTime canceledAtUtc;
}

/// Common response surface consumed by strict receipt verification.
abstract interface class BackupCommittedItemsResponse {
  BackupBatchReference get reference;
  List<BackupCommittedItem> get committedItems;
}

Map<String, String> _freezeFileMapping(
  Map<String, String> source,
  BackupManifest manifest,
) {
  final entries = source.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final mediaKeys = <String>{};

  for (final entry in entries) {
    _validateIdentifier(entry.key, 'fileIdToMediaKey.fileId');
    _validateIdentifier(entry.value, 'fileIdToMediaKey.mediaKey');
    if (!mediaKeys.add(entry.value)) {
      throw ArgumentError.value(
        entry.value,
        'fileIdToMediaKey',
        'Each mediaKey must map to exactly one fileId',
      );
    }
  }

  final manifestKeys = {
    for (final item in manifest.items) item.snapshotItem.mediaKey,
  };
  if (!_sameSet(mediaKeys, manifestKeys)) {
    final missing = manifestKeys.difference(mediaKeys).toList()..sort();
    final unknown = mediaKeys.difference(manifestKeys).toList()..sort();
    throw ArgumentError.value(
      source,
      'fileIdToMediaKey',
      'Must cover the current manifest exactly'
          '${missing.isEmpty ? '' : '; missing: ${missing.join(', ')}'}'
          '${unknown.isEmpty ? '' : '; unknown: ${unknown.join(', ')}'}',
    );
  }

  return UnmodifiableMapView(
    <String, String>{for (final entry in entries) entry.key: entry.value},
  );
}

List<String> _freezeIdentifiers(Iterable<String> source, String fieldName) {
  final result = List<String>.of(source);
  final seen = <String>{};
  for (final value in result) {
    _validateIdentifier(value, fieldName);
    if (!seen.add(value)) {
      throw ArgumentError.value(
          value, fieldName, 'Must not contain duplicates');
    }
  }
  return List<String>.unmodifiable(result);
}

List<BackupCommittedItem> _freezeCommittedItems(
  Iterable<BackupCommittedItem> source,
) {
  final result = List<BackupCommittedItem>.of(source);
  final seen = <String>{};
  for (final item in result) {
    if (!seen.add(item.mediaKey)) {
      throw ArgumentError.value(
        item.mediaKey,
        'committedItems',
        'Duplicate mediaKey',
      );
    }
  }
  return List<BackupCommittedItem>.unmodifiable(result);
}

void _validateIdentifier(String value, String fieldName) {
  if (value.trim().isEmpty || _containsControlCharacter(value)) {
    throw ArgumentError.value(
      value,
      fieldName,
      'Must be non-empty and contain no control characters',
    );
  }
}

void _validateSha256(String value, String fieldName) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      fieldName,
      'Must be 64 lowercase hexadecimal characters',
    );
  }
}

void _validateNonNegative(int value, String fieldName) {
  if (value < 0) {
    throw ArgumentError.value(value, fieldName, 'Must not be negative');
  }
}

void _validateUtc(DateTime value, String fieldName) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, fieldName, 'Must be UTC');
  }
}

void _validateRelativePath(String value) {
  if (_containsControlCharacter(value) || value.contains(r'\')) {
    throw ArgumentError.value(
      value,
      'relativePath',
      r'Must use `/` separators and contain no control characters',
    );
  }
  if (value.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(value)) {
    throw ArgumentError.value(value, 'relativePath', 'Must be relative');
  }
  if (value.isNotEmpty && !value.endsWith('/')) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'Must be empty or end with `/`',
    );
  }
  final segments = value.isEmpty
      ? const <String>[]
      : value.substring(0, value.length - 1).split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw ArgumentError.value(
      value,
      'relativePath',
      'Must be normalized',
    );
  }
}

void _validateDisplayName(String value) {
  if (value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains(r'\') ||
      _containsControlCharacter(value)) {
    throw ArgumentError.value(
      value,
      'displayName',
      'Must be a single non-empty path component',
    );
  }
}

bool _containsControlCharacter(String value) {
  return value.codeUnits.any((codeUnit) => codeUnit < 0x20);
}

bool _sameSet(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

void _validateManifestIdentity({
  required BackupManifest manifest,
  required String targetFingerprint,
  required String manifestSha256,
  required BackupManifestDigest digester,
}) {
  _validateIdentifier(targetFingerprint, 'targetFingerprint');
  _validateSha256(manifestSha256, 'manifestSha256');
  final calculatedDigest = digester.calculate(manifest);
  if (manifestSha256 != calculatedDigest) {
    throw ArgumentError.value(
      manifestSha256,
      'manifestSha256',
      'Does not match the canonical manifest JSON',
    );
  }
}
