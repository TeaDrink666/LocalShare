import 'package:localsend_app/features/backup/manifest/backup_manifest.dart';
import 'package:sqlite3/sqlite3.dart';

/// Durable receiver-side evidence that a backup item was completely written.
///
/// A verified row records that the receiver persisted the bytes at least once.
/// Deliberately, this store never checks [BackupReceiptItem.finalPath] again:
/// users may move a successfully backed-up file out of the inbox afterwards.
final class BackupReceiptStore {
  BackupReceiptStore._(this._database) {
    _initializeSchema();
  }

  /// Opens or creates a receipt database at [path].
  factory BackupReceiptStore.open(String path) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Must not be empty');
    }
    return BackupReceiptStore._(sqlite3.open(path));
  }

  /// Creates an isolated in-memory store, primarily for tests.
  factory BackupReceiptStore.memory() {
    return BackupReceiptStore._(sqlite3.openInMemory());
  }

  final Database _database;
  bool _closed = false;

  /// Creates a batch or merges another page/subset of its manifest items.
  ///
  /// Repeating an identical prepare is idempotent. Reusing the same
  /// `(sourceDevice, profileId, batchId)` for a different target, manifest
  /// schema/creation identity, or item metadata throws
  /// [BackupReceiptConflict]. Item count and total bytes may shrink after the
  /// phone confirms a partial receipt and rewrites its pending manifest to the
  /// remaining subset. No part of a conflicting subset is persisted because
  /// the entire merge is a single transaction.
  void prepare(
    BackupManifest manifest, {
    required String targetFingerprint,
    Iterable<BackupManifestItem>? items,
  }) {
    _ensureOpen();
    _validateIdentifier(
      targetFingerprint,
      argumentName: 'targetFingerprint',
    );

    final manifestItems = <String, BackupManifestItem>{
      for (final item in manifest.items) item.snapshotItem.mediaKey: item,
    };
    final selectedItems = List<BackupManifestItem>.of(
      items ?? manifest.items,
    );
    final selectedKeys = <String>{};
    for (final item in selectedItems) {
      final mediaKey = item.snapshotItem.mediaKey;
      final manifestItem = manifestItems[mediaKey];
      if (manifestItem == null || !_sameManifestItem(manifestItem, item)) {
        throw ArgumentError.value(
          mediaKey,
          'items',
          'Every prepared item must exactly match the supplied manifest',
        );
      }
      if (!selectedKeys.add(mediaKey)) {
        throw ArgumentError.value(
          mediaKey,
          'items',
          'Duplicate mediaKey in prepared subset',
        );
      }
    }

    _transaction(() {
      final key = BackupBatchKey.fromManifest(manifest);
      final existingBatch = _selectBatch(key);
      if (existingBatch == null) {
        _database.execute(
          '''
          INSERT INTO backup_receipt_batches (
            source_device,
            profile_id,
            batch_id,
            target_fingerprint,
            manifest_schema_version,
            manifest_created_at_utc_us,
            manifest_item_count,
            manifest_total_bytes
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            key.sourceDevice,
            key.profileId,
            key.batchId,
            targetFingerprint,
            manifest.schemaVersion,
            manifest.createdAtUtc.microsecondsSinceEpoch,
            manifest.itemCount,
            manifest.totalBytes,
          ],
        );
      } else if (!_batchMatchesManifest(
        existingBatch,
        manifest,
        targetFingerprint,
      )) {
        throw BackupReceiptConflict(
          'Batch ${key.describe()} is already associated with a different '
          'target or manifest',
        );
      }

      for (final item in selectedItems) {
        final existingItem = _selectItem(
          key,
          item.snapshotItem.mediaKey,
        );
        if (existingItem == null) {
          _insertPreparedItem(key, item);
        } else if (!_receiptMetadataMatches(existingItem, item)) {
          throw BackupReceiptConflict(
            'mediaKey ${item.snapshotItem.mediaKey} in ${key.describe()} '
            'was already prepared with different metadata',
          );
        }
      }
    });
  }

  /// Records the final destination selected for an upload before bytes commit.
  ///
  /// Calling this again with the same path while the item is still writing is
  /// idempotent. A writing row exposes enough expected metadata for startup
  /// recovery to validate or discard a staged transfer.
  void markWriting(
    BackupBatchKey batch,
    String mediaKey, {
    required String finalPath,
  }) {
    _ensureOpen();
    _validateIdentifier(mediaKey, argumentName: 'mediaKey');
    _validatePath(finalPath);

    _transaction(() {
      final item = _requireItem(batch, mediaKey);
      switch (item.status) {
        case BackupReceiptStatus.prepared:
          _database.execute(
            '''
            UPDATE backup_receipt_items
            SET status = ?, final_path = ?
            WHERE source_device = ?
              AND profile_id = ?
              AND batch_id = ?
              AND media_key = ?
            ''',
            [
              BackupReceiptStatus.writing.databaseValue,
              finalPath,
              batch.sourceDevice,
              batch.profileId,
              batch.batchId,
              mediaKey,
            ],
          );
        case BackupReceiptStatus.writing:
          if (item.finalPath != finalPath) {
            throw BackupReceiptConflict(
              'Writing item $mediaKey in ${batch.describe()} already uses '
              'a different final path',
            );
          }
        case BackupReceiptStatus.ready:
          throw BackupReceiptStateException(
            'Ready item $mediaKey in ${batch.describe()} cannot return to '
            'the writing state',
          );
        case BackupReceiptStatus.verified:
          throw BackupReceiptStateException(
            'Verified item $mediaKey in ${batch.describe()} cannot return to '
            'the writing state',
          );
      }
    });
  }

  /// Atomically promotes a writing item to durable, receiver-verified state.
  ///
  /// [actualSizeBytes] must equal the manifest size. If the sender supplied an
  /// expected SHA-256 digest, [actualSha256] is mandatory and must match it.
  /// An identical repeated call is accepted to make response-loss retries
  /// safe; the original verification timestamp remains authoritative.
  void markVerified(
    BackupBatchKey batch,
    String mediaKey, {
    required int actualSizeBytes,
    required String? actualSha256,
    required DateTime verifiedAtUtc,
  }) {
    _ensureOpen();
    _validateIdentifier(mediaKey, argumentName: 'mediaKey');
    if (actualSizeBytes < 0) {
      throw ArgumentError.value(
        actualSizeBytes,
        'actualSizeBytes',
        'Must not be negative',
      );
    }
    _validateSha256(actualSha256, argumentName: 'actualSha256');
    _validateUtc(verifiedAtUtc, argumentName: 'verifiedAtUtc');

    _transaction(() {
      final item = _requireItem(batch, mediaKey);
      if (actualSizeBytes != item.expectedSizeBytes) {
        throw BackupReceiptVerificationException(
          'Size verification failed for $mediaKey: expected '
          '${item.expectedSizeBytes}, received $actualSizeBytes',
        );
      }
      if (item.expectedSha256 != null && actualSha256 != item.expectedSha256) {
        throw BackupReceiptVerificationException(
          'SHA-256 verification failed for $mediaKey',
        );
      }

      switch (item.status) {
        case BackupReceiptStatus.prepared:
          throw BackupReceiptStateException(
            'Item $mediaKey in ${batch.describe()} must be marked writing '
            'before it can be verified',
          );
        case BackupReceiptStatus.writing:
          _database.execute(
            '''
            UPDATE backup_receipt_items
            SET status = ?,
                actual_size_bytes = ?,
                actual_sha256 = ?,
                verified_at_utc_us = ?
            WHERE source_device = ?
              AND profile_id = ?
              AND batch_id = ?
              AND media_key = ?
            ''',
            [
              BackupReceiptStatus.verified.databaseValue,
              actualSizeBytes,
              actualSha256,
              verifiedAtUtc.microsecondsSinceEpoch,
              batch.sourceDevice,
              batch.profileId,
              batch.batchId,
              mediaKey,
            ],
          );
        case BackupReceiptStatus.ready:
          if (item.actualSizeBytes != actualSizeBytes ||
              item.actualSha256 != actualSha256) {
            throw BackupReceiptConflict(
              'Ready item $mediaKey in ${batch.describe()} has a different '
              'actual byte signature',
            );
          }
          _database.execute(
            '''
            UPDATE backup_receipt_items
            SET status = ?, verified_at_utc_us = ?
            WHERE source_device = ?
              AND profile_id = ?
              AND batch_id = ?
              AND media_key = ?
            ''',
            [
              BackupReceiptStatus.verified.databaseValue,
              verifiedAtUtc.microsecondsSinceEpoch,
              batch.sourceDevice,
              batch.profileId,
              batch.batchId,
              mediaKey,
            ],
          );
        case BackupReceiptStatus.verified:
          if (item.actualSizeBytes != actualSizeBytes ||
              item.actualSha256 != actualSha256) {
            throw BackupReceiptConflict(
              'Verified item $mediaKey in ${batch.describe()} already has a '
              'different actual byte signature',
            );
          }
      }
    });
  }

  /// Persists the verified temporary-file signature immediately before its
  /// same-directory atomic rename.
  void markReady(
    BackupBatchKey batch,
    String mediaKey, {
    required int actualSizeBytes,
    required String actualSha256,
  }) {
    _ensureOpen();
    _validateIdentifier(mediaKey, argumentName: 'mediaKey');
    if (actualSizeBytes < 0) {
      throw ArgumentError.value(actualSizeBytes, 'actualSizeBytes');
    }
    _validateSha256(actualSha256, argumentName: 'actualSha256');
    _transaction(() {
      final item = _requireItem(batch, mediaKey);
      if (item.status != BackupReceiptStatus.writing) {
        throw BackupReceiptStateException(
          'Only a writing item can become ready: $mediaKey',
        );
      }
      if (actualSizeBytes != item.expectedSizeBytes ||
          (item.expectedSha256 != null &&
              item.expectedSha256 != actualSha256)) {
        throw BackupReceiptVerificationException(
          'Ready signature does not match the manifest for $mediaKey',
        );
      }
      _database.execute(
        '''
        UPDATE backup_receipt_items
        SET status = ?, actual_size_bytes = ?, actual_sha256 = ?
        WHERE source_device = ?
          AND profile_id = ?
          AND batch_id = ?
          AND media_key = ?
        ''',
        [
          BackupReceiptStatus.ready.databaseValue,
          actualSizeBytes,
          actualSha256,
          batch.sourceDevice,
          batch.profileId,
          batch.batchId,
          mediaKey,
        ],
      );
    });
  }

  /// Returns an interrupted item to the prepared state after recovery proved
  /// that its published path is not a valid copy.
  ///
  /// The file itself is deliberately left untouched: it may have been moved
  /// or replaced by the user. A retry will choose a non-conflicting inbox
  /// destination instead of deleting user data.
  void resetWriting(BackupBatchKey batch, String mediaKey) {
    _ensureOpen();
    _validateIdentifier(mediaKey, argumentName: 'mediaKey');
    _transaction(() {
      final item = _requireItem(batch, mediaKey);
      if (item.status != BackupReceiptStatus.writing &&
          item.status != BackupReceiptStatus.ready) {
        throw BackupReceiptStateException(
          'Only a writing item can be reset: $mediaKey in ${batch.describe()}',
        );
      }
      _database.execute(
        '''
        UPDATE backup_receipt_items
        SET status = ?,
            final_path = NULL,
            actual_size_bytes = NULL,
            actual_sha256 = NULL
        WHERE source_device = ?
          AND profile_id = ?
          AND batch_id = ?
          AND media_key = ?
        ''',
        [
          BackupReceiptStatus.prepared.databaseValue,
          batch.sourceDevice,
          batch.profileId,
          batch.batchId,
          mediaKey,
        ],
      );
    });
  }

  /// Returns verified receipts whose stored manifest signature exactly matches
  /// the corresponding item in [manifest].
  ///
  /// No filesystem lookup occurs here. Moving a file after verification does
  /// not revoke its receipt.
  List<BackupReceiptItem> verifiedItemsMatching(
    BackupManifest manifest, {
    required String targetFingerprint,
  }) {
    _ensureOpen();
    _validateIdentifier(
      targetFingerprint,
      argumentName: 'targetFingerprint',
    );
    final key = BackupBatchKey.fromManifest(manifest);
    final batch = _selectBatch(key);
    if (batch == null ||
        !_batchMatchesManifest(batch, manifest, targetFingerprint)) {
      return const <BackupReceiptItem>[];
    }

    final manifestItems = <String, BackupManifestItem>{
      for (final item in manifest.items) item.snapshotItem.mediaKey: item,
    };
    final result = _database.select(
      '''
      SELECT *
      FROM backup_receipt_items
      WHERE source_device = ?
        AND profile_id = ?
        AND batch_id = ?
        AND status = ?
      ORDER BY media_key
      ''',
      [
        key.sourceDevice,
        key.profileId,
        key.batchId,
        BackupReceiptStatus.verified.databaseValue,
      ],
    );
    final matches = <BackupReceiptItem>[];
    for (final row in result) {
      final receipt = _readItem(row);
      final manifestItem = manifestItems[receipt.mediaKey];
      if (manifestItem != null &&
          _receiptMetadataMatches(receipt, manifestItem)) {
        matches.add(receipt);
      }
    }
    return List<BackupReceiptItem>.unmodifiable(matches);
  }

  /// Convenience view of [verifiedItemsMatching] for acknowledgement payloads.
  Set<String> verifiedMediaKeysMatching(
    BackupManifest manifest, {
    required String targetFingerprint,
  }) {
    return Set<String>.unmodifiable(
      verifiedItemsMatching(
        manifest,
        targetFingerprint: targetFingerprint,
      ).map((item) => item.mediaKey),
    );
  }

  /// Returns every persisted item in [batch], ordered by media key.
  List<BackupReceiptItem> batchItems(BackupBatchKey batch) {
    _ensureOpen();
    final result = _database.select(
      '''
      SELECT *
      FROM backup_receipt_items
      WHERE source_device = ?
        AND profile_id = ?
        AND batch_id = ?
      ORDER BY media_key
      ''',
      [batch.sourceDevice, batch.profileId, batch.batchId],
    );
    return List<BackupReceiptItem>.unmodifiable(result.map(_readItem));
  }

  /// Returns interrupted writes, optionally restricted to one batch.
  ///
  /// Each result includes its final path and expected size/hash, allowing the
  /// receiver to inspect a staged file after restart without trusting it.
  List<BackupReceiptItem> writingItems({BackupBatchKey? batch}) {
    _ensureOpen();
    final ResultSet result;
    if (batch == null) {
      result = _database.select(
        '''
        SELECT *
        FROM backup_receipt_items
        WHERE status = ?
        ORDER BY source_device, profile_id, batch_id, media_key
        ''',
        [BackupReceiptStatus.writing.databaseValue],
      );
    } else {
      result = _database.select(
        '''
        SELECT *
        FROM backup_receipt_items
        WHERE source_device = ?
          AND profile_id = ?
          AND batch_id = ?
          AND status = ?
        ORDER BY media_key
        ''',
        [
          batch.sourceDevice,
          batch.profileId,
          batch.batchId,
          BackupReceiptStatus.writing.databaseValue,
        ],
      );
    }
    return List<BackupReceiptItem>.unmodifiable(result.map(_readItem));
  }

  /// Returns both in-progress streams and files that reached the durable
  /// pre-rename signature state before the process stopped.
  List<BackupReceiptItem> interruptedItems({BackupBatchKey? batch}) {
    _ensureOpen();
    final ResultSet result;
    if (batch == null) {
      result = _database.select(
        '''
        SELECT * FROM backup_receipt_items
        WHERE status IN (?, ?)
        ORDER BY source_device, profile_id, batch_id, media_key
        ''',
        [
          BackupReceiptStatus.writing.databaseValue,
          BackupReceiptStatus.ready.databaseValue,
        ],
      );
    } else {
      result = _database.select(
        '''
        SELECT * FROM backup_receipt_items
        WHERE source_device = ?
          AND profile_id = ?
          AND batch_id = ?
          AND status IN (?, ?)
        ORDER BY media_key
        ''',
        [
          batch.sourceDevice,
          batch.profileId,
          batch.batchId,
          BackupReceiptStatus.writing.databaseValue,
          BackupReceiptStatus.ready.databaseValue,
        ],
      );
    }
    return List<BackupReceiptItem>.unmodifiable(result.map(_readItem));
  }

  /// Flushes and closes the underlying SQLite connection.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _database.dispose();
  }

  void _initializeSchema() {
    _database.execute('PRAGMA foreign_keys = ON');
    _transaction(() {
      _database.execute(
        '''
        CREATE TABLE IF NOT EXISTS backup_receipt_batches (
          source_device TEXT NOT NULL,
          profile_id TEXT NOT NULL,
          batch_id TEXT NOT NULL,
          target_fingerprint TEXT NOT NULL,
          manifest_schema_version INTEGER NOT NULL,
          manifest_created_at_utc_us INTEGER NOT NULL,
          manifest_item_count INTEGER NOT NULL CHECK (manifest_item_count >= 0),
          manifest_total_bytes INTEGER NOT NULL CHECK (manifest_total_bytes >= 0),
          PRIMARY KEY (source_device, profile_id, batch_id)
        ) WITHOUT ROWID
        ''',
      );
      _database.execute(
        '''
        CREATE TABLE IF NOT EXISTS backup_receipt_items (
          source_device TEXT NOT NULL,
          profile_id TEXT NOT NULL,
          batch_id TEXT NOT NULL,
          media_key TEXT NOT NULL,
          relative_path TEXT NOT NULL,
          display_name TEXT NOT NULL,
          expected_size_bytes INTEGER NOT NULL CHECK (expected_size_bytes >= 0),
          modified_at_seconds INTEGER NOT NULL CHECK (modified_at_seconds >= 0),
          generation_modified INTEGER CHECK (generation_modified >= 0),
          mime_type TEXT NOT NULL,
          expected_sha256 TEXT,
          status TEXT NOT NULL CHECK (status IN ('prepared', 'writing', 'ready', 'verified')),
          final_path TEXT,
          actual_size_bytes INTEGER CHECK (actual_size_bytes >= 0),
          actual_sha256 TEXT,
          verified_at_utc_us INTEGER,
          PRIMARY KEY (source_device, profile_id, batch_id, media_key),
          FOREIGN KEY (source_device, profile_id, batch_id)
            REFERENCES backup_receipt_batches (
              source_device,
              profile_id,
              batch_id
            )
            ON DELETE CASCADE,
          CHECK (
            (status = 'prepared'
              AND final_path IS NULL
              AND actual_size_bytes IS NULL
              AND actual_sha256 IS NULL
              AND verified_at_utc_us IS NULL)
            OR
            (status = 'writing'
              AND final_path IS NOT NULL
              AND actual_size_bytes IS NULL
              AND actual_sha256 IS NULL
              AND verified_at_utc_us IS NULL)
            OR
            (status = 'ready'
              AND final_path IS NOT NULL
              AND actual_size_bytes IS NOT NULL
              AND actual_sha256 IS NOT NULL
              AND verified_at_utc_us IS NULL)
            OR
            (status = 'verified'
              AND final_path IS NOT NULL
              AND actual_size_bytes IS NOT NULL
              AND verified_at_utc_us IS NOT NULL)
          )
        ) WITHOUT ROWID
        ''',
      );
      _database.execute(
        '''
        CREATE INDEX IF NOT EXISTS backup_receipt_items_status_idx
        ON backup_receipt_items (status)
        ''',
      );
      _database.execute('PRAGMA user_version = 1');
    });
  }

  _StoredBatch? _selectBatch(BackupBatchKey key) {
    final result = _database.select(
      '''
      SELECT *
      FROM backup_receipt_batches
      WHERE source_device = ? AND profile_id = ? AND batch_id = ?
      ''',
      [key.sourceDevice, key.profileId, key.batchId],
    );
    if (result.isEmpty) {
      return null;
    }
    final row = result.single;
    return _StoredBatch(
      key: key,
      targetFingerprint: row['target_fingerprint'] as String,
      schemaVersion: row['manifest_schema_version'] as int,
      createdAtUtc: _dateTime(row['manifest_created_at_utc_us'] as int),
    );
  }

  BackupReceiptItem? _selectItem(BackupBatchKey batch, String mediaKey) {
    final result = _database.select(
      '''
      SELECT *
      FROM backup_receipt_items
      WHERE source_device = ?
        AND profile_id = ?
        AND batch_id = ?
        AND media_key = ?
      ''',
      [batch.sourceDevice, batch.profileId, batch.batchId, mediaKey],
    );
    return result.isEmpty ? null : _readItem(result.single);
  }

  BackupReceiptItem _requireItem(BackupBatchKey batch, String mediaKey) {
    final item = _selectItem(batch, mediaKey);
    if (item == null) {
      throw BackupReceiptStateException(
        'No prepared receipt item $mediaKey exists in ${batch.describe()}',
      );
    }
    return item;
  }

  void _insertPreparedItem(
    BackupBatchKey batch,
    BackupManifestItem item,
  ) {
    final media = item.snapshotItem;
    _database.execute(
      '''
      INSERT INTO backup_receipt_items (
        source_device,
        profile_id,
        batch_id,
        media_key,
        relative_path,
        display_name,
        expected_size_bytes,
        modified_at_seconds,
        generation_modified,
        mime_type,
        expected_sha256,
        status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        batch.sourceDevice,
        batch.profileId,
        batch.batchId,
        media.mediaKey,
        media.relativePath,
        media.displayName,
        media.sizeBytes,
        media.modifiedAtSeconds,
        media.generationModified,
        media.mimeType,
        item.sha256,
        BackupReceiptStatus.prepared.databaseValue,
      ],
    );
  }

  BackupReceiptItem _readItem(Row row) {
    final status = BackupReceiptStatus.fromDatabase(
      row['status'] as String,
    );
    final verifiedMicros = row['verified_at_utc_us'] as int?;
    return BackupReceiptItem(
      batch: BackupBatchKey(
        sourceDevice: row['source_device'] as String,
        profileId: row['profile_id'] as String,
        batchId: row['batch_id'] as String,
      ),
      mediaKey: row['media_key'] as String,
      relativePath: row['relative_path'] as String,
      displayName: row['display_name'] as String,
      expectedSizeBytes: row['expected_size_bytes'] as int,
      modifiedAtSeconds: row['modified_at_seconds'] as int,
      generationModified: row['generation_modified'] as int?,
      mimeType: row['mime_type'] as String,
      expectedSha256: row['expected_sha256'] as String?,
      status: status,
      finalPath: row['final_path'] as String?,
      actualSizeBytes: row['actual_size_bytes'] as int?,
      actualSha256: row['actual_sha256'] as String?,
      verifiedAtUtc: verifiedMicros == null ? null : _dateTime(verifiedMicros),
    );
  }

  bool _batchMatchesManifest(
    _StoredBatch batch,
    BackupManifest manifest,
    String targetFingerprint,
  ) {
    return batch.key == BackupBatchKey.fromManifest(manifest) &&
        batch.targetFingerprint == targetFingerprint &&
        batch.schemaVersion == manifest.schemaVersion &&
        batch.createdAtUtc == manifest.createdAtUtc;
  }

  T _transaction<T>(T Function() action) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      try {
        _database.execute('ROLLBACK');
      } on Object {
        // Preserve the original failure if SQLite has already rolled back.
      }
      rethrow;
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('BackupReceiptStore is closed');
    }
  }
}

/// Composite identity of one sender-created backup batch.
final class BackupBatchKey {
  const BackupBatchKey({
    required this.sourceDevice,
    required this.profileId,
    required this.batchId,
  });

  factory BackupBatchKey.fromManifest(BackupManifest manifest) {
    return BackupBatchKey(
      sourceDevice: manifest.sourceDevice,
      profileId: manifest.profileId,
      batchId: manifest.batchId,
    );
  }

  final String sourceDevice;
  final String profileId;
  final String batchId;

  String describe() => '($sourceDevice, $profileId, $batchId)';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BackupBatchKey &&
            sourceDevice == other.sourceDevice &&
            profileId == other.profileId &&
            batchId == other.batchId;
  }

  @override
  int get hashCode => Object.hash(sourceDevice, profileId, batchId);
}

enum BackupReceiptStatus {
  prepared('prepared'),
  writing('writing'),
  ready('ready'),
  verified('verified');

  const BackupReceiptStatus(this.databaseValue);

  final String databaseValue;

  static BackupReceiptStatus fromDatabase(String value) {
    return switch (value) {
      'prepared' => BackupReceiptStatus.prepared,
      'writing' => BackupReceiptStatus.writing,
      'ready' => BackupReceiptStatus.ready,
      'verified' => BackupReceiptStatus.verified,
      _ => throw StateError('Unknown backup receipt status: $value'),
    };
  }
}

/// Immutable receiver-side state for one manifest item.
final class BackupReceiptItem {
  const BackupReceiptItem({
    required this.batch,
    required this.mediaKey,
    required this.relativePath,
    required this.displayName,
    required this.expectedSizeBytes,
    required this.modifiedAtSeconds,
    required this.generationModified,
    required this.mimeType,
    required this.expectedSha256,
    required this.status,
    required this.finalPath,
    required this.actualSizeBytes,
    required this.actualSha256,
    required this.verifiedAtUtc,
  });

  final BackupBatchKey batch;
  final String mediaKey;
  final String relativePath;
  final String displayName;
  final int expectedSizeBytes;
  final int modifiedAtSeconds;
  final int? generationModified;
  final String mimeType;
  final String? expectedSha256;
  final BackupReceiptStatus status;
  final String? finalPath;
  final int? actualSizeBytes;
  final String? actualSha256;
  final DateTime? verifiedAtUtc;
}

final class BackupReceiptConflict implements Exception {
  const BackupReceiptConflict(this.message);

  final String message;

  @override
  String toString() => 'BackupReceiptConflict: $message';
}

final class BackupReceiptStateException implements Exception {
  const BackupReceiptStateException(this.message);

  final String message;

  @override
  String toString() => 'BackupReceiptStateException: $message';
}

final class BackupReceiptVerificationException implements Exception {
  const BackupReceiptVerificationException(this.message);

  final String message;

  @override
  String toString() => 'BackupReceiptVerificationException: $message';
}

final class _StoredBatch {
  const _StoredBatch({
    required this.key,
    required this.targetFingerprint,
    required this.schemaVersion,
    required this.createdAtUtc,
  });

  final BackupBatchKey key;
  final String targetFingerprint;
  final int schemaVersion;
  final DateTime createdAtUtc;
}

bool _sameManifestItem(
  BackupManifestItem left,
  BackupManifestItem right,
) {
  return left.snapshotItem == right.snapshotItem && left.sha256 == right.sha256;
}

bool _receiptMetadataMatches(
  BackupReceiptItem receipt,
  BackupManifestItem item,
) {
  final media = item.snapshotItem;
  return receipt.mediaKey == media.mediaKey &&
      receipt.relativePath == media.relativePath &&
      receipt.displayName == media.displayName &&
      receipt.expectedSizeBytes == media.sizeBytes &&
      receipt.modifiedAtSeconds == media.modifiedAtSeconds &&
      receipt.generationModified == media.generationModified &&
      receipt.mimeType == media.mimeType &&
      receipt.expectedSha256 == item.sha256;
}

DateTime _dateTime(int microsecondsSinceEpoch) {
  return DateTime.fromMicrosecondsSinceEpoch(
    microsecondsSinceEpoch,
    isUtc: true,
  );
}

void _validateIdentifier(String value, {required String argumentName}) {
  if (value.trim().isEmpty || value.codeUnits.any((unit) => unit < 0x20)) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Must be non-empty and contain no control characters',
    );
  }
}

void _validatePath(String value) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(
      value,
      'finalPath',
      'Must be non-empty and contain no NUL character',
    );
  }
}

void _validateUtc(DateTime value, {required String argumentName}) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, argumentName, 'Must be UTC');
  }
}

void _validateSha256(String? value, {required String argumentName}) {
  if (value != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Must be null or 64 lowercase hexadecimal characters',
    );
  }
}
