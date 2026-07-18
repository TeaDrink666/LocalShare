import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest_codec.dart';

/// Calculates the identity of the exact manifest representation sent on wire.
///
/// [BackupManifestCodec] produces canonical JSON, so equivalent manifests have
/// the same digest regardless of their original item iteration order.
final class BackupManifestDigest {
  const BackupManifestDigest({
    this.manifestCodec = const BackupManifestCodec(),
  });

  final BackupManifestCodec manifestCodec;

  String calculate(BackupManifest manifest) {
    final canonicalJson = manifestCodec.encode(manifest);
    return sha256.convert(utf8.encode(canonicalJson)).toString();
  }
}
