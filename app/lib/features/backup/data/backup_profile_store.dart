import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:localsend_app/features/backup/data/backup_target_profile.dart';
import 'package:localsend_app/features/backup/domain/backup_ledger_entry.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/manifest.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _indexSchemaVersion = 1;
const _uuid = Uuid();

final class BackupProfileIndex {
  BackupProfileIndex({
    required Iterable<BackupTargetProfile> profiles,
    required this.selectedProfileId,
  }) : profiles = List<BackupTargetProfile>.unmodifiable(profiles);

  final List<BackupTargetProfile> profiles;
  final String? selectedProfileId;

  BackupTargetProfile? get selectedProfile {
    for (final profile in profiles) {
      if (profile.id == selectedProfileId) {
        return profile;
      }
    }
    return null;
  }
}

/// File-backed storage for small profile metadata and per-profile manifests.
///
/// Pending manifests are deliberately separate from confirmed ledgers. A
/// transfer being offered or downloaded never advances the confirmed ledger;
/// [confirmPending] is the only operation that does so.
final class BackupProfileStore {
  BackupProfileStore({
    required Directory rootDirectory,
    BackupManifestCodec codec = const BackupManifestCodec(),
  })  : _rootDirectory = rootDirectory,
        _codec = codec;

  static Future<BackupProfileStore> openDefault() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final store = BackupProfileStore(
      rootDirectory: Directory(
        p.join(supportDirectory.path, 'localshare', 'backup'),
      ),
    );
    await store.initialize();
    return store;
  }

  final Directory _rootDirectory;
  final BackupManifestCodec _codec;

  File get _indexFile => File(p.join(_rootDirectory.path, 'profiles.json'));

  Future<void> initialize() => _rootDirectory.create(recursive: true);

  Future<BackupProfileIndex> loadIndex() async {
    await initialize();
    if (!await _indexFile.exists()) {
      return BackupProfileIndex(profiles: const [], selectedProfileId: null);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(await _indexFile.readAsString());
    } on FormatException catch (error) {
      throw FormatException('Invalid backup profile index: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Backup profile index must be an object.');
    }
    const expectedKeys = {'schemaVersion', 'selectedProfileId', 'profiles'};
    if (decoded.keys.toSet().length != expectedKeys.length ||
        !decoded.keys.toSet().containsAll(expectedKeys)) {
      throw const FormatException('Invalid backup profile index fields.');
    }
    if (decoded['schemaVersion'] != _indexSchemaVersion) {
      throw FormatException(
        'Unsupported backup profile schema: ${decoded['schemaVersion']}',
      );
    }

    final rawProfiles = decoded['profiles'];
    final selectedProfileId = decoded['selectedProfileId'];
    if (rawProfiles is! List<Object?> ||
        (selectedProfileId != null && selectedProfileId is! String)) {
      throw const FormatException('Invalid backup profile index values.');
    }

    final ids = <String>{};
    final deviceFingerprints = <String>{};
    final profiles = rawProfiles.map((rawProfile) {
      if (rawProfile is! Map<String, Object?>) {
        throw const FormatException('Backup profile must be an object.');
      }
      final profile = BackupTargetProfile.fromJson(rawProfile);
      if (!ids.add(profile.id)) {
        throw FormatException('Duplicate backup profile ID: ${profile.id}');
      }
      final fingerprint = profile.deviceFingerprint;
      if (fingerprint != null && !deviceFingerprints.add(fingerprint)) {
        throw FormatException(
          'Duplicate backup target device: $fingerprint',
        );
      }
      return profile;
    }).toList(growable: false);

    if (selectedProfileId != null && !ids.contains(selectedProfileId)) {
      throw const FormatException('Selected backup profile does not exist.');
    }
    return BackupProfileIndex(
      profiles: profiles,
      selectedProfileId: selectedProfileId as String?,
    );
  }

  Future<BackupTargetProfile> ensureDefaultProfile(String displayName) async {
    final index = await loadIndex();
    if (index.profiles.isNotEmpty) {
      final selected = index.selectedProfile ?? index.profiles.first;
      if (index.selectedProfile == null) {
        await _saveIndex(
          BackupProfileIndex(
            profiles: index.profiles,
            selectedProfileId: selected.id,
          ),
        );
      }
      return selected;
    }
    return createProfile(displayName);
  }

  Future<BackupTargetProfile> createProfile(String displayName) async {
    final index = await loadIndex();
    final profile = BackupTargetProfile(
      id: _uuid.v4(),
      displayName: displayName.trim(),
      createdAtUtc: DateTime.now().toUtc(),
      lastConfirmedAtUtc: null,
    )..validate();
    await _saveIndex(
      BackupProfileIndex(
        profiles: [...index.profiles, profile],
        selectedProfileId: profile.id,
      ),
    );
    return profile;
  }

  Future<void> selectProfile(String profileId) async {
    _validateProfileId(profileId);
    final index = await loadIndex();
    if (!index.profiles.any((profile) => profile.id == profileId)) {
      throw StateError('Backup profile does not exist: $profileId');
    }
    await _saveIndex(
      BackupProfileIndex(
        profiles: index.profiles,
        selectedProfileId: profileId,
      ),
    );
  }

  /// Permanently associates a backup ledger with one discovered client.
  ///
  /// Older profiles have no fingerprint. They are bound the first time the
  /// user sends that profile to a nearby computer. A bound profile can never
  /// silently move to another computer, and one computer cannot own two
  /// independent ledgers by accident.
  Future<BackupTargetProfile> bindProfileToDevice({
    required String profileId,
    required String deviceFingerprint,
  }) async {
    _validateProfileId(profileId);
    _validateDeviceFingerprint(deviceFingerprint);
    final index = await loadIndex();
    final target =
        index.profiles.where((profile) => profile.id == profileId).firstOrNull;
    if (target == null) {
      throw StateError('Backup profile does not exist: $profileId');
    }
    final existingOwner = index.profiles.where(
      (profile) =>
          profile.id != profileId &&
          profile.deviceFingerprint == deviceFingerprint,
    );
    if (existingOwner.isNotEmpty) {
      throw StateError(
        'This device is already linked to backup profile: '
        '${existingOwner.first.id}',
      );
    }
    if (target.deviceFingerprint != null &&
        target.deviceFingerprint != deviceFingerprint) {
      throw StateError(
        'Backup profile is linked to a different device: $profileId',
      );
    }
    if (target.deviceFingerprint == deviceFingerprint) {
      return target;
    }

    final bound = target.copyWith(deviceFingerprint: deviceFingerprint);
    await _saveIndex(
      BackupProfileIndex(
        profiles: index.profiles
            .map((profile) => profile.id == profileId ? bound : profile)
            .toList(growable: false),
        selectedProfileId: index.selectedProfileId,
      ),
    );
    return bound;
  }

  Future<BackupManifest?> loadPending(String profileId) {
    return _loadManifest(_manifestFile(profileId, pending: true), profileId);
  }

  Future<List<BackupLedgerEntry>> loadConfirmedLedger(
    String profileId,
  ) async {
    final manifest = await _loadManifest(
      _manifestFile(profileId, pending: false),
      profileId,
    );
    if (manifest == null) {
      return const [];
    }
    return List<BackupLedgerEntry>.unmodifiable(
      manifest.items.map(
        (item) => BackupLedgerEntry.fromConfirmedItem(item.snapshotItem),
      ),
    );
  }

  Future<void> savePending(BackupManifest manifest) async {
    await _requireProfile(manifest.profileId);
    final file = _manifestFile(manifest.profileId, pending: true);
    if (await file.exists()) {
      throw StateError(
        'Backup profile already has an unresolved pending manifest: '
        '${manifest.profileId}',
      );
    }
    await _atomicWrite(
      file,
      _codec.encode(manifest),
    );
  }

  Future<void> discardPending(String profileId) async {
    final file = _manifestFile(profileId, pending: true);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Confirms all pending items, or only [mediaKeys] for partial browser saves.
  ///
  /// Unconfirmed items remain pending. A newly confirmed item replaces an old
  /// entry with the same destination path, while no file is deleted remotely.
  Future<int> confirmPending(
    String profileId, {
    Set<String>? mediaKeys,
  }) async {
    final pending = await loadPending(profileId);
    if (pending == null) {
      return 0;
    }
    final pendingByKey = {
      for (final item in pending.items) item.snapshotItem.mediaKey: item,
    };
    final keysToConfirm = mediaKeys ?? pendingByKey.keys.toSet();
    final unknownKeys = keysToConfirm.difference(pendingByKey.keys.toSet());
    if (unknownKeys.isNotEmpty) {
      throw ArgumentError.value(
        unknownKeys,
        'mediaKeys',
        'Contains items that are not pending.',
      );
    }
    if (keysToConfirm.isEmpty) {
      return 0;
    }

    final confirmedEntries = await loadConfirmedLedger(profileId);
    final confirmedByKey = {
      for (final entry in confirmedEntries) entry.mediaKey: entry,
    };
    for (final key in keysToConfirm) {
      final snapshot = pendingByKey[key]!.snapshotItem;
      final destinationPath = '${snapshot.relativePath}${snapshot.displayName}';
      confirmedByKey.removeWhere(
        (otherKey, entry) =>
            otherKey != key &&
            '${entry.relativePath}${entry.displayName}' == destinationPath,
      );
      confirmedByKey[key] = BackupLedgerEntry.fromConfirmedItem(snapshot);
    }

    final now = DateTime.now().toUtc();
    final confirmedManifest = BackupManifest.fromMediaItems(
      batchId: 'ledger-${now.microsecondsSinceEpoch}',
      profileId: profileId,
      sourceDevice: pending.sourceDevice,
      createdAtUtc: now,
      items: confirmedByKey.values.map(_snapshotFromLedger),
    );
    await _atomicWrite(
      _manifestFile(profileId, pending: false),
      _codec.encode(confirmedManifest),
    );

    final remaining = pending.items
        .where((item) => !keysToConfirm.contains(item.snapshotItem.mediaKey))
        .toList(growable: false);
    if (remaining.isEmpty) {
      await discardPending(profileId);
    } else {
      await _atomicWrite(
        _manifestFile(profileId, pending: true),
        _codec.encode(
          BackupManifest(
            batchId: pending.batchId,
            profileId: pending.profileId,
            sourceDevice: pending.sourceDevice,
            createdAtUtc: pending.createdAtUtc,
            items: remaining,
          ),
        ),
      );
    }
    await _markProfileConfirmed(profileId, now);
    return keysToConfirm.length;
  }

  Future<void> _markProfileConfirmed(String profileId, DateTime now) async {
    final index = await loadIndex();
    await _saveIndex(
      BackupProfileIndex(
        profiles: index.profiles
            .map(
              (profile) => profile.id == profileId
                  ? profile.copyWith(lastConfirmedAtUtc: now)
                  : profile,
            )
            .toList(growable: false),
        selectedProfileId: index.selectedProfileId,
      ),
    );
  }

  Future<void> _requireProfile(String profileId) async {
    _validateProfileId(profileId);
    final index = await loadIndex();
    if (!index.profiles.any((profile) => profile.id == profileId)) {
      throw StateError('Backup profile does not exist: $profileId');
    }
  }

  File _manifestFile(String profileId, {required bool pending}) {
    _validateProfileId(profileId);
    final prefix = pending ? 'pending' : 'confirmed';
    return File(p.join(_rootDirectory.path, '$prefix-$profileId.json'));
  }

  Future<BackupManifest?> _loadManifest(
    File file,
    String profileId,
  ) async {
    if (!await file.exists()) {
      return null;
    }
    final manifest = _codec.decode(await file.readAsString());
    if (manifest.profileId != profileId) {
      throw const FormatException('Backup manifest profile mismatch.');
    }
    return manifest;
  }

  Future<void> _saveIndex(BackupProfileIndex index) async {
    final document = <String, Object?>{
      'schemaVersion': _indexSchemaVersion,
      'selectedProfileId': index.selectedProfileId,
      'profiles': index.profiles.map((profile) => profile.toJson()).toList(),
    };
    await _atomicWrite(_indexFile, jsonEncode(document));
  }

  Future<void> _atomicWrite(File destination, String contents) async {
    await initialize();
    final temporary = File('${destination.path}.tmp');
    final backup = File('${destination.path}.bak');
    await temporary.writeAsString(contents, flush: true);
    try {
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await destination.exists()) {
        await destination.rename(backup.path);
      }
      await temporary.rename(destination.path);
      if (await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}

MediaSnapshotItem _snapshotFromLedger(BackupLedgerEntry entry) {
  return MediaSnapshotItem(
    mediaKey: entry.mediaKey,
    relativePath: entry.relativePath,
    displayName: entry.displayName,
    sizeBytes: entry.sizeBytes,
    modifiedAtSeconds: entry.modifiedAtSeconds,
    generationModified: entry.generationModified,
    mimeType: entry.mimeType,
  );
}

void _validateProfileId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'profileId', 'Invalid profile ID.');
  }
}

void _validateDeviceFingerprint(String value) {
  if (value.trim().isEmpty ||
      value.length > 256 ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw ArgumentError.value(
      value,
      'deviceFingerprint',
      'Invalid device fingerprint.',
    );
  }
}
