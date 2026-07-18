import 'dart:convert';

import 'package:localsend_app/features/backup/manifest/backup_manifest_codec.dart';
import 'package:localsend_app/features/backup/protocol/backup_manifest_digest.dart';
import 'package:localsend_app/features/backup/protocol/backup_protocol_models.dart';
import 'package:localsend_app/features/backup/protocol/backup_protocol_routes.dart';

/// Strict JSON codec for the LocalShare backup extension.
///
/// Decoders reject missing and unknown fields. String encoders recursively
/// sort object keys so logged or persisted protocol documents are stable.
final class BackupProtocolCodec {
  const BackupProtocolCodec({
    this.manifestCodec = const BackupManifestCodec(),
  });

  final BackupManifestCodec manifestCodec;

  Map<String, Object?> manifestMetadataToJson(BackupManifestMetadata value) {
    return <String, Object?>{
      'protocolVersion': value.protocolVersion,
      'manifest': jsonDecode(manifestCodec.encode(value.manifest)),
      'manifestSha256': value.manifestSha256,
      'targetFingerprint': value.targetFingerprint,
    };
  }

  BackupManifestMetadata manifestMetadataFromJson(Object? value) {
    final document = _requireObject(value, r'$');
    _requireExactKeys(
      document,
      const {
        'protocolVersion',
        'manifest',
        'manifestSha256',
        'targetFingerprint',
      },
      r'$',
    );
    _requireProtocolVersion(document['protocolVersion'], r'$.protocolVersion');
    final manifestDocument =
        _requireObject(document['manifest'], r'$.manifest');
    final manifest = manifestCodec.decode(jsonEncode(manifestDocument));
    return _construct(r'$', () {
      return BackupManifestMetadata(
        manifest: manifest,
        manifestSha256: _requireString(
          document['manifestSha256'],
          r'$.manifestSha256',
        ),
        targetFingerprint: _requireString(
          document['targetFingerprint'],
          r'$.targetFingerprint',
        ),
        digester: BackupManifestDigest(manifestCodec: manifestCodec),
      );
    });
  }

  Map<String, Object?> prepareMetadataToJson(BackupPrepareMetadata value) {
    return <String, Object?>{
      'protocolVersion': value.protocolVersion,
      'manifest': jsonDecode(manifestCodec.encode(value.manifest)),
      'manifestSha256': value.manifestSha256,
      'fileIdToMediaKey': value.fileIdToMediaKey,
      'targetFingerprint': value.targetFingerprint,
    };
  }

  BackupPrepareMetadata prepareMetadataFromJson(Object? value) {
    final document = _requireObject(value, r'$');
    _requireExactKeys(
      document,
      const {
        'protocolVersion',
        'manifest',
        'manifestSha256',
        'fileIdToMediaKey',
        'targetFingerprint',
      },
      r'$',
    );
    _requireProtocolVersion(document['protocolVersion'], r'$.protocolVersion');

    final manifestDocument =
        _requireObject(document['manifest'], r'$.manifest');
    final manifest = manifestCodec.decode(jsonEncode(manifestDocument));
    final mappingDocument = _requireObject(
      document['fileIdToMediaKey'],
      r'$.fileIdToMediaKey',
    );
    final mapping = <String, String>{
      for (final entry in mappingDocument.entries)
        entry.key: _requireString(
          entry.value,
          r'$.fileIdToMediaKey.' + entry.key,
        ),
    };

    return _construct(r'$', () {
      return BackupPrepareMetadata(
        manifest: manifest,
        manifestSha256: _requireString(
          document['manifestSha256'],
          r'$.manifestSha256',
        ),
        fileIdToMediaKey: mapping,
        targetFingerprint: _requireString(
          document['targetFingerprint'],
          r'$.targetFingerprint',
        ),
        digester: BackupManifestDigest(manifestCodec: manifestCodec),
      );
    });
  }

  /// Reads the namespaced extension from an existing prepare-upload request.
  ///
  /// The surrounding request may contain LocalSend's normal `info` and
  /// `files` fields. The extension object itself is decoded strictly.
  BackupPrepareMetadata prepareMetadataFromRequestJson(
    Map<String, Object?> request,
  ) {
    if (!request.containsKey(localShareBackupMetadataField)) {
      throw const FormatException(
        r'$.localShareBackup is required',
      );
    }
    return prepareMetadataFromJson(request[localShareBackupMetadataField]);
  }

  /// Returns a copy of a prepare-upload request with the extension attached.
  Map<String, Object?> attachPrepareMetadata(
    Map<String, Object?> request,
    BackupPrepareMetadata metadata,
  ) {
    if (request.containsKey(localShareBackupMetadataField)) {
      throw ArgumentError.value(
        request[localShareBackupMetadataField],
        localShareBackupMetadataField,
        'Prepare request already contains backup metadata',
      );
    }
    return <String, Object?>{
      ...request,
      localShareBackupMetadataField: prepareMetadataToJson(metadata),
    };
  }

  String encodePlanRequest(BackupPlanRequest value) {
    return _encode(planRequestToJson(value));
  }

  Map<String, Object?> planRequestToJson(BackupPlanRequest value) {
    return <String, Object?>{
      'protocolVersion': value.protocolVersion,
      localShareBackupMetadataField: prepareMetadataToJson(value.metadata),
    };
  }

  BackupPlanRequest decodePlanRequest(String source) {
    return planRequestFromJson(_decode(source));
  }

  BackupPlanRequest planRequestFromJson(Object? value) {
    final document = _protocolDocument(
      value,
      const {'protocolVersion', localShareBackupMetadataField},
    );
    return BackupPlanRequest(
      metadata: prepareMetadataFromJson(
        document[localShareBackupMetadataField],
      ),
    );
  }

  String encodePlanResponse(BackupPlanResponse value) {
    return _encode(planResponseToJson(value));
  }

  Map<String, Object?> planResponseToJson(BackupPlanResponse value) {
    return <String, Object?>{
      'protocolVersion': value.protocolVersion,
      'reference': _referenceToJson(value.reference),
      'requiredMediaKeys': value.requiredMediaKeys,
      'committedItems': value.committedItems.map(_committedItemToJson).toList(),
    };
  }

  BackupPlanResponse decodePlanResponse(String source) {
    return planResponseFromJson(_decode(source));
  }

  BackupPlanResponse planResponseFromJson(Object? value) {
    final document = _protocolDocument(
      value,
      const {
        'protocolVersion',
        'reference',
        'requiredMediaKeys',
        'committedItems',
      },
    );
    return _construct(r'$', () {
      return BackupPlanResponse(
        reference: _referenceFromJson(document['reference'], r'$.reference'),
        requiredMediaKeys: _stringList(
          document['requiredMediaKeys'],
          r'$.requiredMediaKeys',
        ),
        committedItems: _committedItemsFromJson(
          document['committedItems'],
          r'$.committedItems',
        ),
      );
    });
  }

  String encodeCommitRequest(BackupCommitRequest value) {
    return _encode(commitRequestToJson(value));
  }

  Map<String, Object?> commitRequestToJson(BackupCommitRequest value) {
    return _metadataRequestToJson(value.protocolVersion, value.metadata);
  }

  BackupCommitRequest decodeCommitRequest(String source) {
    return commitRequestFromJson(_decode(source));
  }

  BackupCommitRequest commitRequestFromJson(Object? value) {
    final document = _metadataRequestDocument(value);
    return BackupCommitRequest(
      metadata: manifestMetadataFromJson(
        document[localShareBackupMetadataField],
      ),
    );
  }

  String encodeCommitResponse(BackupCommitResponse value) {
    return _encode(commitResponseToJson(value));
  }

  Map<String, Object?> commitResponseToJson(BackupCommitResponse value) {
    return _committedResponseToJson(
      value.protocolVersion,
      value.reference,
      value.committedItems,
    );
  }

  BackupCommitResponse decodeCommitResponse(String source) {
    return commitResponseFromJson(_decode(source));
  }

  BackupCommitResponse commitResponseFromJson(Object? value) {
    final document = _committedResponseDocument(value);
    return _construct(r'$', () {
      return BackupCommitResponse(
        reference: _referenceFromJson(document['reference'], r'$.reference'),
        committedItems: _committedItemsFromJson(
          document['committedItems'],
          r'$.committedItems',
        ),
      );
    });
  }

  String encodeReceiptRequest(BackupReceiptRequest value) {
    return _encode(receiptRequestToJson(value));
  }

  Map<String, Object?> receiptRequestToJson(BackupReceiptRequest value) {
    return _metadataRequestToJson(value.protocolVersion, value.metadata);
  }

  BackupReceiptRequest decodeReceiptRequest(String source) {
    return receiptRequestFromJson(_decode(source));
  }

  BackupReceiptRequest receiptRequestFromJson(Object? value) {
    final document = _metadataRequestDocument(value);
    return BackupReceiptRequest(
      metadata: manifestMetadataFromJson(
        document[localShareBackupMetadataField],
      ),
    );
  }

  String encodeReceiptResponse(BackupReceiptResponse value) {
    return _encode(receiptResponseToJson(value));
  }

  Map<String, Object?> receiptResponseToJson(BackupReceiptResponse value) {
    return _committedResponseToJson(
      value.protocolVersion,
      value.reference,
      value.committedItems,
    );
  }

  BackupReceiptResponse decodeReceiptResponse(String source) {
    return receiptResponseFromJson(_decode(source));
  }

  BackupReceiptResponse receiptResponseFromJson(Object? value) {
    final document = _committedResponseDocument(value);
    return _construct(r'$', () {
      return BackupReceiptResponse(
        reference: _referenceFromJson(document['reference'], r'$.reference'),
        committedItems: _committedItemsFromJson(
          document['committedItems'],
          r'$.committedItems',
        ),
      );
    });
  }

  String encodeCancelRequest(BackupCancelRequest value) {
    return _encode(cancelRequestToJson(value));
  }

  Map<String, Object?> cancelRequestToJson(BackupCancelRequest value) {
    return _referenceRequestToJson(value.protocolVersion, value.reference);
  }

  BackupCancelRequest decodeCancelRequest(String source) {
    return cancelRequestFromJson(_decode(source));
  }

  BackupCancelRequest cancelRequestFromJson(Object? value) {
    final document = _referenceRequestDocument(value);
    return BackupCancelRequest(
      reference: _referenceFromJson(document['reference'], r'$.reference'),
    );
  }

  String encodeCancelResponse(BackupCancelResponse value) {
    return _encode(cancelResponseToJson(value));
  }

  Map<String, Object?> cancelResponseToJson(BackupCancelResponse value) {
    return <String, Object?>{
      'protocolVersion': value.protocolVersion,
      'reference': _referenceToJson(value.reference),
      'canceledAtUtc': value.canceledAtUtc.toIso8601String(),
    };
  }

  BackupCancelResponse decodeCancelResponse(String source) {
    return cancelResponseFromJson(_decode(source));
  }

  BackupCancelResponse cancelResponseFromJson(Object? value) {
    final document = _protocolDocument(
      value,
      const {'protocolVersion', 'reference', 'canceledAtUtc'},
    );
    return _construct(r'$', () {
      return BackupCancelResponse(
        reference: _referenceFromJson(document['reference'], r'$.reference'),
        canceledAtUtc: _requireUtcTimestamp(
          document['canceledAtUtc'],
          r'$.canceledAtUtc',
        ),
      );
    });
  }

  Map<String, Object?> _protocolDocument(
    Object? value,
    Set<String> fields,
  ) {
    final document = _requireObject(value, r'$');
    _requireExactKeys(document, fields, r'$');
    _requireProtocolVersion(document['protocolVersion'], r'$.protocolVersion');
    return document;
  }

  Map<String, Object?> _referenceRequestToJson(
    int protocolVersion,
    BackupBatchReference reference,
  ) {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'reference': _referenceToJson(reference),
    };
  }

  Map<String, Object?> _metadataRequestToJson(
    int protocolVersion,
    BackupManifestMetadata metadata,
  ) {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      localShareBackupMetadataField: manifestMetadataToJson(metadata),
    };
  }

  Map<String, Object?> _metadataRequestDocument(Object? value) {
    return _protocolDocument(
      value,
      const {'protocolVersion', localShareBackupMetadataField},
    );
  }

  Map<String, Object?> _referenceRequestDocument(Object? value) {
    return _protocolDocument(
      value,
      const {'protocolVersion', 'reference'},
    );
  }

  Map<String, Object?> _committedResponseToJson(
    int protocolVersion,
    BackupBatchReference reference,
    List<BackupCommittedItem> committedItems,
  ) {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'reference': _referenceToJson(reference),
      'committedItems': committedItems.map(_committedItemToJson).toList(),
    };
  }

  Map<String, Object?> _committedResponseDocument(Object? value) {
    return _protocolDocument(
      value,
      const {'protocolVersion', 'reference', 'committedItems'},
    );
  }

  Map<String, Object?> _referenceToJson(BackupBatchReference value) {
    return <String, Object?>{
      'batchId': value.batchId,
      'profileId': value.profileId,
      'sourceDevice': value.sourceDevice,
      'targetFingerprint': value.targetFingerprint,
      'manifestSha256': value.manifestSha256,
    };
  }

  BackupBatchReference _referenceFromJson(Object? value, String path) {
    final document = _requireObject(value, path);
    _requireExactKeys(
      document,
      const {
        'batchId',
        'profileId',
        'sourceDevice',
        'targetFingerprint',
        'manifestSha256',
      },
      path,
    );
    return _construct(path, () {
      return BackupBatchReference(
        batchId: _requireString(document['batchId'], '$path.batchId'),
        profileId: _requireString(document['profileId'], '$path.profileId'),
        sourceDevice: _requireString(
          document['sourceDevice'],
          '$path.sourceDevice',
        ),
        targetFingerprint: _requireString(
          document['targetFingerprint'],
          '$path.targetFingerprint',
        ),
        manifestSha256: _requireString(
          document['manifestSha256'],
          '$path.manifestSha256',
        ),
      );
    });
  }

  Map<String, Object?> _committedItemToJson(BackupCommittedItem value) {
    return <String, Object?>{
      'mediaKey': value.mediaKey,
      'relativePath': value.relativePath,
      'displayName': value.displayName,
      'sizeBytes': value.sizeBytes,
      'modifiedAtSeconds': value.modifiedAtSeconds,
      'generationModified': value.generationModified,
      'sha256': value.sha256,
      'verifiedAtUtc': value.verifiedAtUtc.toIso8601String(),
    };
  }

  BackupCommittedItem _committedItemFromJson(Object? value, String path) {
    final document = _requireObject(value, path);
    _requireExactKeys(
      document,
      const {
        'mediaKey',
        'relativePath',
        'displayName',
        'sizeBytes',
        'modifiedAtSeconds',
        'generationModified',
        'sha256',
        'verifiedAtUtc',
      },
      path,
    );
    final generation = document['generationModified'];
    final digest = document['sha256'];
    return _construct(path, () {
      return BackupCommittedItem(
        mediaKey: _requireString(document['mediaKey'], '$path.mediaKey'),
        relativePath: _requireString(
          document['relativePath'],
          '$path.relativePath',
        ),
        displayName: _requireString(
          document['displayName'],
          '$path.displayName',
        ),
        sizeBytes: _requireNonNegativeInt(
          document['sizeBytes'],
          '$path.sizeBytes',
        ),
        modifiedAtSeconds: _requireNonNegativeInt(
          document['modifiedAtSeconds'],
          '$path.modifiedAtSeconds',
        ),
        generationModified: generation == null
            ? null
            : _requireNonNegativeInt(
                generation,
                '$path.generationModified',
              ),
        sha256: digest == null ? null : _requireString(digest, '$path.sha256'),
        verifiedAtUtc: _requireUtcTimestamp(
          document['verifiedAtUtc'],
          '$path.verifiedAtUtc',
        ),
      );
    });
  }

  List<BackupCommittedItem> _committedItemsFromJson(
    Object? value,
    String path,
  ) {
    final items = _requireList(value, path);
    return [
      for (var index = 0; index < items.length; index++)
        _committedItemFromJson(items[index], '$path[$index]'),
    ];
  }
}

String _encode(Map<String, Object?> document) {
  return jsonEncode(_sortObjectKeys(document));
}

Object? _decode(String source) {
  try {
    return jsonDecode(source);
  } on FormatException catch (error) {
    throw FormatException('Invalid backup protocol JSON: ${error.message}');
  }
}

Map<String, Object?> _requireObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be a JSON object');
  }
  return value;
}

List<Object?> _requireList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw FormatException('$path must be a JSON array');
  }
  return value;
}

String _requireString(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string');
  }
  return value;
}

int _requireNonNegativeInt(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer');
  }
  if (value < 0) {
    throw FormatException('$path must not be negative');
  }
  return value;
}

List<String> _stringList(Object? value, String path) {
  final list = _requireList(value, path);
  return [
    for (var index = 0; index < list.length; index++)
      _requireString(list[index], '$path[$index]'),
  ];
}

void _requireProtocolVersion(Object? value, String path) {
  if (value is! int) {
    throw FormatException('$path must be an integer');
  }
  if (value != backupProtocolVersion) {
    throw FormatException('Unsupported backup protocol version: $value');
  }
}

DateTime _requireUtcTimestamp(Object? value, String path) {
  final text = _requireString(value, path);
  if (!text.endsWith('Z')) {
    throw FormatException('$path must use the UTC `Z` designator');
  }
  final DateTime result;
  try {
    result = DateTime.parse(text);
  } on FormatException {
    throw FormatException('$path must be a valid ISO-8601 timestamp');
  }
  if (!result.isUtc) {
    throw FormatException('$path must be UTC');
  }
  return result;
}

void _requireExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
) {
  final actual = value.keys.toSet();
  final missing = expected.difference(actual).toList()..sort();
  final unexpected = actual.difference(expected).toList()..sort();
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    throw FormatException(
      '$path has an invalid field set'
      '${missing.isEmpty ? '' : '; missing: ${missing.join(', ')}'}'
      '${unexpected.isEmpty ? '' : '; unexpected: ${unexpected.join(', ')}'}',
    );
  }
}

T _construct<T>(String path, T Function() constructor) {
  try {
    return constructor();
  } on ArgumentError catch (error) {
    throw FormatException('$path is invalid: ${error.message}');
  }
}

Object? _sortObjectKeys(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortObjectKeys(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sortObjectKeys).toList(growable: false);
  }
  return value;
}
