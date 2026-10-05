import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/features/backup/data/backup_target_profile.dart';
import 'package:localsend_app/features/backup/domain/backup_ledger_entry.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:localsend_app/features/backup/manifest/backup_manifest_codec.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
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

/// SQLite-backed storage for backup profiles, pending batches and confirmed
/// ledgers.
///
/// Pending batches are deliberately separate from confirmed ledgers. A
/// transfer being offered or downloaded never advances the confirmed ledger;
/// [confirmPending] is the only operation that does so.
///
/// The database lives at [rootDirectory]/backup.db. On first open, legacy
/// profiles.json / pending-<id>.json / confirmed-<id>.json files from
/// older builds are imported once and then marked as imported.
final class BackupProfileStore {
  BackupProfileStore({
    required Directory rootDirectory,
  }) : _rootDirectory = rootDirectory;

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
  Database? _database;

  Database get _db => _database ??= _openDatabase();

  Future<void> initialize() async {
    _openDatabase();
  }

  void close() {
    _database?.dispose();
    _database = null;
  }

  Database _openDatabase() {
    _rootDirectory.createSync(recursive: true);
    final database = sqlite3.open(
      p.join(_rootDirectory.path, 'backup.db'),
    );
    database.execute('PRAGMA journal_mode = WAL;');
    database.execute('PRAGMA foreign_keys = ON;');
    _createSchema(database);
    _importLegacyFiles(database);
    return database;
  }

  void _createSchema(Database database) {
    database.execute('CREATE TABLE IF NOT EXISTS profiles ('
        '  id TEXT PRIMARY KEY,'
        '  display_name TEXT NOT NULL,'
        '  created_at_utc INTEGER NOT NULL,'
        '  last_confirmed_at_utc INTEGER,'
        '  device_fingerprint TEXT)');
    database.execute('CREATE TABLE IF NOT EXISTS meta ('
        '  key TEXT PRIMARY KEY,'
        '  value TEXT NOT NULL)');
    database.execute('CREATE TABLE IF NOT EXISTS pending_items ('
        '  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,'
        '  media_key TEXT NOT NULL,'
        '  batch_id TEXT NOT NULL,'
        '  source_device TEXT NOT NULL,'
        '  created_at_utc INTEGER NOT NULL,'
        '  relative_path TEXT NOT NULL,'
        '  display_name TEXT NOT NULL,'
        '  size_bytes INTEGER NOT NULL,'
        '  modified_at_seconds INTEGER NOT NULL,'
        '  generation_modified INTEGER,'
        '  mime_type TEXT NOT NULL,'
        '  sha256 TEXT,'
        '  PRIMARY KEY (profile_id, media_key))');
    database.execute('CREATE TABLE IF NOT EXISTS confirmed_items ('
        '  profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,'
        '  media_key TEXT NOT NULL,'
        '  relative_path TEXT NOT NULL,'
        '  display_name TEXT NOT NULL,'
        '  size_bytes INTEGER NOT NULL,'
        '  modified_at_seconds INTEGER NOT NULL,'
        '  generation_modified INTEGER,'
        '  mime_type TEXT NOT NULL,'
        '  PRIMARY KEY (profile_id, media_key))');
  }

  /// One-time import of the legacy file-based storage format.
  void _importLegacyFiles(Database database) {
    final indexFile = File(p.join(_rootDirectory.path, 'profiles.json'));
    if (!indexFile.existsSync()) {
      return;
    }
    final count = database.select('SELECT COUNT(*) AS c FROM profiles').first['c'] as int;
    if (count > 0) {
      // The database is already populated; leave the legacy files untouched.
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(indexFile.readAsStringSync());
    } on FormatException {
      return; // corrupt legacy index; do not destroy it
    }
    if (decoded is! Map<String, Object?>) {
      return;
    }
    const expectedKeys = {'schemaVersion', 'selectedProfileId', 'profiles'};
    if (decoded.keys.toSet().length != expectedKeys.length ||
        !decoded.keys.toSet().containsAll(expectedKeys) ||
        decoded['schemaVersion'] != _indexSchemaVersion) {
      return;
    }
    final rawProfiles = decoded['profiles'];
    final selectedProfileId = decoded['selectedProfileId'];
    if (rawProfiles is! List<Object?> || (selectedProfileId != null && selectedProfileId is! String)) {
      return;
    }

    final ids = <String>{};
    final deviceFingerprints = <String>{};
    final profiles = <BackupTargetProfile>[];
    for (final rawProfile in rawProfiles) {
      if (rawProfile is! Map<String, Object?>) {
        return;
      }
      final BackupTargetProfile profile;
      try {
        profile = BackupTargetProfile.fromJson(rawProfile);
      } on FormatException {
        return;
      }
      if (!ids.add(profile.id)) {
        return;
      }
      final fingerprint = profile.deviceFingerprint;
      if (fingerprint != null && !deviceFingerprints.add(fingerprint)) {
        return;
      }
      profiles.add(profile);
    }
    if (selectedProfileId != null && !ids.contains(selectedProfileId)) {
      return;
    }

    const codec = BackupManifestCodec();
    try {
      database.execute('BEGIN IMMEDIATE');
      for (final profile in profiles) {
        database.execute(
          'INSERT INTO profiles '
          '(id, display_name, created_at_utc, last_confirmed_at_utc, '
          'device_fingerprint) VALUES (?, ?, ?, ?, ?)',
          [
            profile.id,
            profile.displayName,
            _encodeUtc(profile.createdAtUtc),
            profile.lastConfirmedAtUtc == null ? null : _encodeUtc(profile.lastConfirmedAtUtc!),
            profile.deviceFingerprint,
          ],
        );
        _importLegacyManifest(database, profile.id, pending: true, codec: codec);
        _importLegacyManifest(database, profile.id, pending: false, codec: codec);
      }
      if (selectedProfileId != null) {
        database.execute(
          'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
          ['selected_profile_id', selectedProfileId],
        );
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      return;
    }

    // Mark the legacy files as imported so the next open does not re-import.
    indexFile.renameSync('${indexFile.path}.imported');
    for (final profile in profiles) {
      for (final pending in const [true, false]) {
        final manifest = File(p.join(
          _rootDirectory.path,
          '${pending ? 'pending' : 'confirmed'}-${profile.id}.json',
        ));
        if (manifest.existsSync()) {
          manifest.renameSync('${manifest.path}.imported');
        }
      }
    }
  }

  void _importLegacyManifest(
    Database database,
    String profileId, {
    required bool pending,
    required BackupManifestCodec codec,
  }) {
    final file = File(p.join(
      _rootDirectory.path,
      '${pending ? 'pending' : 'confirmed'}-$profileId.json',
    ));
    if (!file.existsSync()) {
      return;
    }
    final BackupManifest manifest;
    try {
      manifest = codec.decode(file.readAsStringSync());
    } on FormatException {
      return; // skip a corrupt legacy manifest
    }
    if (manifest.profileId != profileId) {
      return;
    }
    for (final item in manifest.items) {
      final snapshot = item.snapshotItem;
      database.execute(
        pending
            ? 'INSERT OR REPLACE INTO pending_items '
                '(profile_id, media_key, batch_id, source_device, '
                'created_at_utc, relative_path, display_name, size_bytes, '
                'modified_at_seconds, generation_modified, mime_type, sha256) '
                'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
            : 'INSERT OR REPLACE INTO confirmed_items '
                '(profile_id, media_key, relative_path, display_name, '
                'size_bytes, modified_at_seconds, generation_modified, '
                'mime_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        pending
            ? [
                profileId,
                snapshot.mediaKey,
                manifest.batchId,
                manifest.sourceDevice,
                _encodeUtc(manifest.createdAtUtc),
                snapshot.relativePath,
                snapshot.displayName,
                snapshot.sizeBytes,
                snapshot.modifiedAtSeconds,
                snapshot.generationModified,
                snapshot.mimeType,
                item.sha256,
              ]
            : [
                profileId,
                snapshot.mediaKey,
                snapshot.relativePath,
                snapshot.displayName,
                snapshot.sizeBytes,
                snapshot.modifiedAtSeconds,
                snapshot.generationModified,
                snapshot.mimeType,
              ],
      );
    }
    // Keep only the pending rows actually listed in the manifest.
    if (pending && manifest.items.isNotEmpty) {
      final keys = manifest.items.map((item) => item.snapshotItem.mediaKey);
      database.execute(
        'DELETE FROM pending_items WHERE profile_id = ? '
        'AND media_key NOT IN (${List.filled(keys.length, '?').join(', ')})',
        [profileId, ...keys],
      );
    }
  }

  Future<BackupProfileIndex> loadIndex() async {
    final database = _db;
    final rows = database.select(
      'SELECT id, display_name, created_at_utc, last_confirmed_at_utc, '
      'device_fingerprint FROM profiles ORDER BY created_at_utc, id',
    );
    final selectedRows = database.select(
      "SELECT value FROM meta WHERE key = 'selected_profile_id'",
    );
    final selectedProfileId = selectedRows.isEmpty ? null : selectedRows.first['value'] as String;
    if (selectedProfileId != null && !rows.any((row) => row['id'] == selectedProfileId)) {
      throw const FormatException('Selected backup profile does not exist.');
    }
    return BackupProfileIndex(
      profiles: rows.map(_profileFromRow).toList(growable: false),
      selectedProfileId: selectedProfileId,
    );
  }

  Future<BackupTargetProfile> ensureDefaultProfile(String displayName) async {
    final index = await loadIndex();
    if (index.profiles.isNotEmpty) {
      final selected = index.selectedProfile ?? index.profiles.first;
      if (index.selectedProfile == null) {
        await _setSelectedProfileId(selected.id);
      }
      return selected;
    }
    return createProfile(displayName);
  }

  Future<BackupTargetProfile> createProfile(String displayName) async {
    final profile = BackupTargetProfile(
      id: _uuid.v4(),
      displayName: displayName.trim(),
      createdAtUtc: DateTime.now().toUtc(),
      lastConfirmedAtUtc: null,
    )..validate();
    final database = _db;
    database.execute(
      'INSERT INTO profiles '
      '(id, display_name, created_at_utc, last_confirmed_at_utc, '
      'device_fingerprint) VALUES (?, ?, ?, NULL, NULL)',
      [profile.id, profile.displayName, _encodeUtc(profile.createdAtUtc)],
    );
    await _setSelectedProfileId(profile.id);
    return profile;
  }

  Future<void> selectProfile(String profileId) async {
    _validateProfileId(profileId);
    final database = _db;
    final rows = database.select(
      'SELECT 1 FROM profiles WHERE id = ?',
      [profileId],
    );
    if (rows.isEmpty) {
      throw StateError('Backup profile does not exist: $profileId');
    }
    await _setSelectedProfileId(profileId);
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
    final database = _db;
    final rows = database.select(
      'SELECT id, display_name, created_at_utc, last_confirmed_at_utc, '
      'device_fingerprint FROM profiles WHERE id = ?',
      [profileId],
    );
    if (rows.isEmpty) {
      throw StateError('Backup profile does not exist: $profileId');
    }
    final existingOwner = database.select(
      'SELECT id FROM profiles WHERE id != ? AND device_fingerprint = ?',
      [profileId, deviceFingerprint],
    );
    if (existingOwner.isNotEmpty) {
      throw StateError(
        'This device is already linked to backup profile: '
        '${existingOwner.first['id']}',
      );
    }
    final target = _profileFromRow(rows.first);
    if (target.deviceFingerprint != null && target.deviceFingerprint != deviceFingerprint) {
      throw StateError(
        'Backup profile is linked to a different device: $profileId',
      );
    }
    if (target.deviceFingerprint == deviceFingerprint) {
      return target;
    }

    database.execute(
      'UPDATE profiles SET device_fingerprint = ? WHERE id = ?',
      [deviceFingerprint, profileId],
    );
    return target.copyWith(deviceFingerprint: deviceFingerprint);
  }

  Future<BackupManifest?> loadPending(String profileId) async {
    _validateProfileId(profileId);
    final rows = _db.select(
      'SELECT media_key, batch_id, source_device, created_at_utc, '
      'relative_path, display_name, size_bytes, modified_at_seconds, '
      'generation_modified, mime_type, sha256 '
      'FROM pending_items WHERE profile_id = ?',
      [profileId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final first = rows.first;
    return _manifestFromRows(
      profileId: profileId,
      batchId: first['batch_id'] as String,
      sourceDevice: first['source_device'] as String,
      createdAtUtc: _decodeUtc(first['created_at_utc'] as int),
      rows: rows,
    );
  }

  Future<List<BackupLedgerEntry>> loadConfirmedLedger(
    String profileId,
  ) async {
    _validateProfileId(profileId);
    final rows = _db.select(
      'SELECT media_key, relative_path, display_name, size_bytes, '
      'modified_at_seconds, generation_modified, mime_type '
      'FROM confirmed_items WHERE profile_id = ?',
      [profileId],
    );
    return List<BackupLedgerEntry>.unmodifiable(
      rows.map(
        (row) => BackupLedgerEntry.fromConfirmedItem(_snapshotFromRow(row)),
      ),
    );
  }

  Future<void> savePending(BackupManifest manifest) async {
    await _requireProfile(manifest.profileId);
    final database = _db;
    final existing = database.select(
      'SELECT 1 FROM pending_items WHERE profile_id = ? LIMIT 1',
      [manifest.profileId],
    );
    if (existing.isNotEmpty) {
      throw StateError(
        'Backup profile already has an unresolved pending manifest: '
        '${manifest.profileId}',
      );
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      for (final item in manifest.items) {
        final snapshot = item.snapshotItem;
        database.execute(
          'INSERT INTO pending_items '
          '(profile_id, media_key, batch_id, source_device, '
          'created_at_utc, relative_path, display_name, size_bytes, '
          'modified_at_seconds, generation_modified, mime_type, sha256) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            manifest.profileId,
            snapshot.mediaKey,
            manifest.batchId,
            manifest.sourceDevice,
            _encodeUtc(manifest.createdAtUtc),
            snapshot.relativePath,
            snapshot.displayName,
            snapshot.sizeBytes,
            snapshot.modifiedAtSeconds,
            snapshot.generationModified,
            snapshot.mimeType,
            item.sha256,
          ],
        );
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> discardPending(String profileId) async {
    _db.execute(
      'DELETE FROM pending_items WHERE profile_id = ?',
      [profileId],
    );
  }

  /// Confirms all pending items, or only [mediaKeys] for partial saves.
  ///
  /// Unconfirmed items remain pending. A newly confirmed item replaces an old
  /// entry with the same destination path, while no file is deleted remotely.
  Future<int> confirmPending(
    String profileId, {
    Set<String>? mediaKeys,
  }) async {
    _validateProfileId(profileId);
    final database = _db;
    final rows = database.select(
      'SELECT media_key, batch_id, source_device, created_at_utc, '
      'relative_path, display_name, size_bytes, modified_at_seconds, '
      'generation_modified, mime_type, sha256 '
      'FROM pending_items WHERE profile_id = ?',
      [profileId],
    );
    if (rows.isEmpty) {
      return 0;
    }
    final pendingByKey = <String, _PendingRow>{};
    for (final row in rows) {
      pendingByKey[row['media_key'] as String] = _PendingRow(row);
    }
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

    final confirmedRows = database.select(
      'SELECT media_key, relative_path, display_name, size_bytes, '
      'modified_at_seconds, generation_modified, mime_type '
      'FROM confirmed_items WHERE profile_id = ?',
      [profileId],
    );
    final confirmedByKey = <String, BackupLedgerEntry>{};
    for (final row in confirmedRows) {
      final entry = BackupLedgerEntry.fromConfirmedItem(_snapshotFromRow(row));
      confirmedByKey[entry.mediaKey] = entry;
    }
    for (final key in keysToConfirm) {
      final snapshot = pendingByKey[key]!.snapshot;
      final destinationPath = '${snapshot.relativePath}${snapshot.displayName}';
      confirmedByKey.removeWhere(
        (otherKey, entry) => otherKey != key && '${entry.relativePath}${entry.displayName}' == destinationPath,
      );
      confirmedByKey[key] = BackupLedgerEntry.fromConfirmedItem(snapshot);
    }

    final now = DateTime.now().toUtc();
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute(
        'DELETE FROM confirmed_items WHERE profile_id = ?',
        [profileId],
      );
      for (final entry in confirmedByKey.values) {
        database.execute(
          'INSERT INTO confirmed_items '
          '(profile_id, media_key, relative_path, display_name, size_bytes, '
          'modified_at_seconds, generation_modified, mime_type) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            profileId,
            entry.mediaKey,
            entry.relativePath,
            entry.displayName,
            entry.sizeBytes,
            entry.modifiedAtSeconds,
            entry.generationModified,
            entry.mimeType,
          ],
        );
      }
      database.execute(
        'DELETE FROM pending_items WHERE profile_id = ? AND media_key IN '
        '(${List.filled(keysToConfirm.length, '?').join(', ')})',
        [profileId, ...keysToConfirm],
      );
      database.execute(
        'UPDATE profiles SET last_confirmed_at_utc = ? WHERE id = ?',
        [_encodeUtc(now), profileId],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    return keysToConfirm.length;
  }

  Future<void> _setSelectedProfileId(String profileId) async {
    _db.execute(
      'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
      ['selected_profile_id', profileId],
    );
  }

  Future<void> _requireProfile(String profileId) async {
    _validateProfileId(profileId);
    final rows = _db.select(
      'SELECT 1 FROM profiles WHERE id = ?',
      [profileId],
    );
    if (rows.isEmpty) {
      throw StateError('Backup profile does not exist: $profileId');
    }
  }

  BackupTargetProfile _profileFromRow(Row row) {
    return BackupTargetProfile(
      id: row['id'] as String,
      displayName: row['display_name'] as String,
      createdAtUtc: _decodeUtc(row['created_at_utc'] as int),
      lastConfirmedAtUtc: row['last_confirmed_at_utc'] == null ? null : _decodeUtc(row['last_confirmed_at_utc'] as int),
      deviceFingerprint: row['device_fingerprint'] as String?,
    )..validate();
  }

  MediaSnapshotItem _snapshotFromRow(Row row) {
    return MediaSnapshotItem(
      mediaKey: row['media_key'] as String,
      relativePath: row['relative_path'] as String,
      displayName: row['display_name'] as String,
      sizeBytes: row['size_bytes'] as int,
      modifiedAtSeconds: row['modified_at_seconds'] as int,
      generationModified: row['generation_modified'] as int?,
      mimeType: row['mime_type'] as String,
    );
  }

  BackupManifest _manifestFromRows({
    required String profileId,
    required String batchId,
    required String sourceDevice,
    required DateTime createdAtUtc,
    required List<Row> rows,
  }) {
    return BackupManifest(
      batchId: batchId,
      profileId: profileId,
      sourceDevice: sourceDevice,
      createdAtUtc: createdAtUtc,
      items: rows.map(
        (row) => BackupManifestItem(
          snapshotItem: _snapshotFromRow(row),
          sha256: row['sha256'] as String?,
        ),
      ),
    );
  }
}

final class _PendingRow {
  _PendingRow(Row row)
      : snapshot = MediaSnapshotItem(
          mediaKey: row['media_key'] as String,
          relativePath: row['relative_path'] as String,
          displayName: row['display_name'] as String,
          sizeBytes: row['size_bytes'] as int,
          modifiedAtSeconds: row['modified_at_seconds'] as int,
          generationModified: row['generation_modified'] as int?,
          mimeType: row['mime_type'] as String,
        );

  final MediaSnapshotItem snapshot;
}

int _encodeUtc(DateTime value) => value.toUtc().microsecondsSinceEpoch;

DateTime _decodeUtc(int value) => DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);

void _validateProfileId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'profileId', 'Invalid profile ID.');
  }
}

void _validateDeviceFingerprint(String value) {
  if (value.trim().isEmpty || value.length > 256 || value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw ArgumentError.value(
      value,
      'deviceFingerprint',
      'Invalid device fingerprint.',
    );
  }
}
