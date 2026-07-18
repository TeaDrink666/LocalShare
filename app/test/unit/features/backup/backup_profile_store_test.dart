import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/features/backup/data/backup_profile_store.dart';
import 'package:localsend_app/features/backup/data/backup_target_profile.dart';
import 'package:localsend_app/features/backup/domain/backup_ledger_entry.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/manifest.dart';
import 'package:test/test.dart';

void main() {
  late Directory rootDirectory;
  late BackupProfileStore store;

  setUp(() async {
    rootDirectory = await Directory.systemTemp.createTemp(
      'localshare-backup-profile-store-',
    );
    store = BackupProfileStore(rootDirectory: rootDirectory);
  });

  tearDown(() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  });

  group('profile index persistence', () {
    test('starts empty and creates a selected default profile once', () async {
      final empty = await store.loadIndex();

      expect(empty.profiles, isEmpty);
      expect(empty.selectedProfileId, isNull);
      expect(empty.selectedProfile, isNull);

      final created = await store.ensureDefaultProfile('  Home PC  ');
      final again = await store.ensureDefaultProfile('Ignored name');
      final index = await store.loadIndex();

      expect(created.displayName, 'Home PC');
      expect(created.id, matches(r'^[A-Za-z0-9_-]{1,80}$'));
      expect(created.createdAtUtc.isUtc, isTrue);
      expect(created.lastConfirmedAtUtc, isNull);
      expect(created.deviceFingerprint, isNull);
      expect(again.id, created.id);
      expect(index.profiles, hasLength(1));
      expect(index.selectedProfileId, created.id);
      expect(index.selectedProfile?.id, created.id);
      expect(() => index.profiles.clear(), throwsUnsupportedError);
    });

    test('persists profiles and selection across store instances', () async {
      final home = await store.createProfile('Home PC');
      final work = await store.createProfile('Work PC');
      await store.selectProfile(home.id);

      final reopened = BackupProfileStore(rootDirectory: rootDirectory);
      final index = await reopened.loadIndex();

      expect(index.profiles.map((profile) => profile.id), [home.id, work.id]);
      expect(
        index.profiles.map((profile) => profile.displayName),
        ['Home PC', 'Work PC'],
      );
      expect(index.profiles.first.createdAtUtc, home.createdAtUtc);
      expect(index.selectedProfileId, home.id);
      expect(index.selectedProfile?.displayName, 'Home PC');
    });

    test('selecting a profile validates both its shape and existence',
        () async {
      final profile = await store.createProfile('Home PC');

      await expectLater(
        store.selectProfile('../outside'),
        throwsArgumentError,
      );
      await expectLater(
        store.selectProfile('missing-profile'),
        throwsA(isA<StateError>()),
      );

      expect((await store.loadIndex()).selectedProfileId, profile.id);
    });

    test('binds one profile to one nearby computer permanently', () async {
      final home = await store.createProfile('Home PC');
      final work = await store.createProfile('Work PC');

      final bound = await store.bindProfileToDevice(
        profileId: home.id,
        deviceFingerprint: 'windows-home-fingerprint',
      );
      expect(bound.deviceFingerprint, 'windows-home-fingerprint');
      expect(
        (await store.loadIndex())
            .profiles
            .singleWhere((profile) => profile.id == home.id)
            .deviceFingerprint,
        'windows-home-fingerprint',
      );

      await expectLater(
        store.bindProfileToDevice(
          profileId: home.id,
          deviceFingerprint: 'different-computer',
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        store.bindProfileToDevice(
          profileId: work.id,
          deviceFingerprint: 'windows-home-fingerprint',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('pending and confirmed persistence', () {
    test('keeps pending batches isolated by target profile', () async {
      final home = await store.createProfile('Home PC');
      final work = await store.createProfile('Work PC');
      final homeItem = _media(key: 'home:1', name: 'home.jpg');
      final workItem = _media(key: 'work:1', name: 'work.jpg');
      await store.savePending(_manifest(home.id, [homeItem]));
      await store.savePending(_manifest(work.id, [workItem]));

      expect(await store.confirmPending(home.id), 1);

      expect(await store.loadPending(home.id), isNull);
      expect(
        await store.loadConfirmedLedger(home.id),
        [BackupLedgerEntry.fromConfirmedItem(homeItem)],
      );
      expect(
        (await store.loadPending(work.id))?.items.single.snapshotItem,
        workItem,
      );
      expect(await store.loadConfirmedLedger(work.id), isEmpty);

      final index = await store.loadIndex();
      expect(
        index.profiles
            .singleWhere((item) => item.id == home.id)
            .lastConfirmedAtUtc,
        isNotNull,
      );
      expect(
        index.profiles
            .singleWhere((item) => item.id == work.id)
            .lastConfirmedAtUtc,
        isNull,
      );
    });

    test('refuses to replace an unresolved pending batch', () async {
      final profile = await store.createProfile('Home PC');
      final original = _media(key: 'external:original', name: 'original.jpg');
      final replacement = _media(
        key: 'external:replacement',
        name: 'replacement.jpg',
        size: 500,
      );
      await store.savePending(_manifest(profile.id, [original]));
      final pendingFile = File(
        '${rootDirectory.path}${Platform.pathSeparator}'
        'pending-${profile.id}.json',
      );
      final originalBytes = await pendingFile.readAsBytes();

      await expectLater(
        store.savePending(_manifest(profile.id, [replacement])),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(profile.id),
          ),
        ),
      );

      expect(await pendingFile.readAsBytes(), originalBytes);
      expect(
        (await store.loadPending(profile.id))?.items.single.snapshotItem,
        original,
      );
      expect(await store.loadConfirmedLedger(profile.id), isEmpty);
      expect(
        (await store.loadIndex()).selectedProfile?.lastConfirmedAtUtc,
        isNull,
      );

      await store.discardPending(profile.id);
      await store.savePending(_manifest(profile.id, [replacement]));
      expect(await store.confirmPending(profile.id), 1);
      await store.savePending(_manifest(profile.id, [original]));

      expect(
        await store.loadConfirmedLedger(profile.id),
        [BackupLedgerEntry.fromConfirmedItem(replacement)],
      );
      expect(
        (await store.loadPending(profile.id))?.items.single.snapshotItem,
        original,
      );
    });

    test('saving or discarding pending data never advances the ledger',
        () async {
      final profile = await store.createProfile('Home PC');
      final original = _media(key: 'external:1', size: 100);
      await store.savePending(_manifest(profile.id, [original]));

      expect(await store.loadConfirmedLedger(profile.id), isEmpty);
      expect(
        (await store.loadIndex()).selectedProfile?.lastConfirmedAtUtc,
        isNull,
      );

      await store.confirmPending(profile.id);
      final confirmedAt =
          (await store.loadIndex()).selectedProfile!.lastConfirmedAtUtc;
      final changed = _media(key: 'external:1', size: 200, modified: 20);
      await store.savePending(_manifest(profile.id, [changed]));

      expect(
        await store.loadConfirmedLedger(profile.id),
        [BackupLedgerEntry.fromConfirmedItem(original)],
      );
      expect(
        (await store.loadIndex()).selectedProfile?.lastConfirmedAtUtc,
        confirmedAt,
      );

      await store.discardPending(profile.id);
      expect(await store.loadPending(profile.id), isNull);
      expect(
        await store.loadConfirmedLedger(profile.id),
        [BackupLedgerEntry.fromConfirmedItem(original)],
      );
      expect(
        (await store.loadIndex()).selectedProfile?.lastConfirmedAtUtc,
        confirmedAt,
      );
    });

    test('partially confirms selected media and leaves the rest pending',
        () async {
      final profile = await store.createProfile('Home PC');
      final first = _media(key: 'external:1', name: '1.jpg');
      final second = _media(key: 'external:2', name: '2.jpg');
      final third = _media(key: 'external:3', name: '3.jpg');
      await store.savePending(
        _manifest(profile.id, [third, first, second]),
      );

      expect(
        await store.confirmPending(
          profile.id,
          mediaKeys: {'external:1', 'external:3'},
        ),
        2,
      );

      expect(
        (await store.loadConfirmedLedger(profile.id))
            .map((entry) => entry.mediaKey),
        ['external:1', 'external:3'],
      );
      final remaining = await store.loadPending(profile.id);
      expect(remaining?.batchId, 'batch-1');
      expect(remaining?.sourceDevice, 'pixel-9');
      expect(
        remaining?.items.map((item) => item.snapshotItem.mediaKey),
        ['external:2'],
      );
      expect(
        (await store.loadIndex()).selectedProfile?.lastConfirmedAtUtc,
        isNotNull,
      );

      expect(await store.confirmPending(profile.id), 1);
      expect(await store.loadPending(profile.id), isNull);
      expect(
        (await store.loadConfirmedLedger(profile.id))
            .map((entry) => entry.mediaKey),
        ['external:1', 'external:2', 'external:3'],
      );
    });

    test('empty and unknown partial confirmations do not mutate state',
        () async {
      final profile = await store.createProfile('Home PC');
      final item = _media(key: 'external:1');
      await store.savePending(_manifest(profile.id, [item]));

      expect(
        await store.confirmPending(profile.id, mediaKeys: const {}),
        0,
      );
      await expectLater(
        store.confirmPending(
          profile.id,
          mediaKeys: {'external:missing'},
        ),
        throwsArgumentError,
      );

      expect(await store.loadConfirmedLedger(profile.id), isEmpty);
      expect(
        (await store.loadPending(profile.id))?.items.single.snapshotItem,
        item,
      );
      expect(
        (await store.loadIndex()).selectedProfile?.lastConfirmedAtUtc,
        isNull,
      );
    });

    test('reloads pending and confirmed state after a restart', () async {
      final profile = await store.createProfile('Home PC');
      final confirmed = _media(key: 'external:1', name: 'saved.jpg');
      final pending = _media(key: 'external:2', name: 'waiting.jpg');
      await store.savePending(_manifest(profile.id, [confirmed, pending]));
      await store.confirmPending(
        profile.id,
        mediaKeys: {confirmed.mediaKey},
      );

      final reopened = BackupProfileStore(rootDirectory: rootDirectory);
      final index = await reopened.loadIndex();

      expect(index.selectedProfile?.lastConfirmedAtUtc, isNotNull);
      expect(
        await reopened.loadConfirmedLedger(profile.id),
        [BackupLedgerEntry.fromConfirmedItem(confirmed)],
      );
      expect(
        (await reopened.loadPending(profile.id))?.items.single.snapshotItem,
        pending,
      );
    });

    test('a newly confirmed item replaces the same destination', () async {
      final profile = await store.createProfile('Home PC');
      final oldItem = _media(
        key: 'external:old',
        path: 'DCIM/Camera/',
        name: 'collision.jpg',
        size: 100,
      );
      await store.savePending(_manifest(profile.id, [oldItem]));
      await store.confirmPending(profile.id);

      final replacement = _media(
        key: 'external:new',
        path: 'DCIM/Camera/',
        name: 'collision.jpg',
        size: 500,
        modified: 99,
      );
      await store.savePending(_manifest(profile.id, [replacement]));
      await store.confirmPending(profile.id);

      expect(
        await store.loadConfirmedLedger(profile.id),
        [BackupLedgerEntry.fromConfirmedItem(replacement)],
      );
    });
  });

  group('validation', () {
    test('rejects invalid profile names and profile JSON', () async {
      for (final name in ['', '   ', 'line\nbreak', 'x' * 81]) {
        await expectLater(
          store.createProfile(name),
          throwsArgumentError,
          reason: 'Expected profile name to be rejected: $name',
        );
      }

      final valid = <String, Object?>{
        'id': 'home-pc',
        'displayName': 'Home PC',
        'createdAtUtc': '2026-07-12T03:04:05.000Z',
        'lastConfirmedAtUtc': null,
      };
      for (final invalid in [
        {...valid, 'id': '../home'},
        {...valid, 'createdAtUtc': '2026-07-12T03:04:05+08:00'},
        {...valid, 'lastConfirmedAtUtc': 'not-a-time'},
        {...valid, 'unexpected': true},
      ]) {
        expect(
          () => BackupTargetProfile.fromJson(invalid),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects malformed, duplicate, and dangling index entries', () async {
      final indexFile = File(
        '${rootDirectory.path}${Platform.pathSeparator}profiles.json',
      );

      await indexFile.writeAsString('{not-json');
      await expectLater(store.loadIndex(), throwsA(isA<FormatException>()));

      final profile = <String, Object?>{
        'id': 'home-pc',
        'displayName': 'Home PC',
        'createdAtUtc': '2026-07-12T03:04:05.000Z',
        'lastConfirmedAtUtc': null,
      };
      await indexFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'selectedProfileId': 'home-pc',
          'profiles': [profile, profile],
        }),
      );
      await expectLater(store.loadIndex(), throwsA(isA<FormatException>()));

      await indexFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'selectedProfileId': 'missing-profile',
          'profiles': [profile],
        }),
      );
      await expectLater(store.loadIndex(), throwsA(isA<FormatException>()));
    });

    test('rejects unknown profiles and mismatched manifest files', () async {
      await expectLater(
        store.savePending(_manifest('missing-profile', [_media()])),
        throwsA(isA<StateError>()),
      );
      expect(
        () => store.loadPending('../outside'),
        throwsArgumentError,
      );

      final profile = await store.createProfile('Home PC');
      const codec = BackupManifestCodec();
      final pendingFile = File(
        '${rootDirectory.path}${Platform.pathSeparator}'
        'pending-${profile.id}.json',
      );
      await pendingFile.writeAsString(
        codec.encode(_manifest('different-profile', [_media()])),
      );

      await expectLater(
        store.loadPending(profile.id),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

BackupManifest _manifest(
  String profileId,
  Iterable<MediaSnapshotItem> items,
) {
  return BackupManifest.fromMediaItems(
    batchId: 'batch-1',
    profileId: profileId,
    sourceDevice: 'pixel-9',
    createdAtUtc: DateTime.utc(2026, 7, 12, 3, 4, 5),
    items: items,
  );
}

MediaSnapshotItem _media({
  String key = 'external:1',
  String path = 'DCIM/Camera/',
  String name = 'IMG_0001.jpg',
  int size = 100,
  int modified = 10,
}) {
  return MediaSnapshotItem(
    mediaKey: key,
    relativePath: path,
    displayName: name,
    sizeBytes: size,
    modifiedAtSeconds: modified,
    generationModified: modified,
    mimeType: 'image/jpeg',
  );
}
