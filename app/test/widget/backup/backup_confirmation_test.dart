import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/backup/data/android_media_catalog.dart';
import 'package:localsend_app/features/backup/data/backup_profile_store.dart';
import 'package:localsend_app/features/backup/data/backup_target_profile.dart';
import 'package:localsend_app/features/backup/domain/media_snapshot.dart';
import 'package:localsend_app/features/backup/manifest/manifest.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/pages/backup/backup_page.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  testWidgets('an existing pending batch waits for automatic verification', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    late Directory temporaryDirectory;
    late BackupProfileStore store;
    late BackupTargetProfile profile;
    late BackupManifest pending;
    await tester.runAsync(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'localshare-backup-confirmation-test-',
      );
      store = BackupProfileStore(rootDirectory: temporaryDirectory);
      profile = await store.createProfile('Studio PC');
      pending = BackupManifest.fromMediaItems(
        batchId: 'batch-1',
        profileId: profile.id,
        sourceDevice: 'phone-1',
        createdAtUtc: DateTime.utc(2026, 7, 12),
        items: const [
          MediaSnapshotItem(
            mediaKey: 'external:1',
            relativePath: 'DCIM/Camera/',
            displayName: 'one.jpg',
            sizeBytes: 1024,
            modifiedAtSeconds: 1,
            generationModified: 1,
            mimeType: 'image/jpeg',
          ),
          MediaSnapshotItem(
            mediaKey: 'external:2',
            relativePath: 'DCIM/Camera/',
            displayName: 'two.mp4',
            sizeBytes: 2048,
            modifiedAtSeconds: 2,
            generationModified: 2,
            mimeType: 'video/mp4',
          ),
        ],
      );
      await store.savePending(pending);
    });
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
    });

    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: BackupPage(
            openStore: () async => store,
            isAndroidOverride: true,
            onOpenNativeTransfer: () async {},
            onOpenReceive: () async {},
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.text(LocalShareCopy.pendingComputerReceipt),
    );

    expect(find.text(LocalShareCopy.pendingComputerReceipt), findsOneWidget);
    expect(
      find.text(LocalShareCopy.pendingComputerReceiptDescription(2)),
      findsOneWidget,
    );
    expect(find.text(LocalShareCopy.pendingConfirmation), findsNothing);
    expect(find.text(LocalShareCopy.confirmSaved), findsNothing);
    expect(find.text(LocalShareCopy.confirmSavedTitle), findsNothing);
  });

  testWidgets('manual confirmation appears only after returning from web send', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    late Directory temporaryDirectory;
    late BackupProfileStore store;
    await tester.runAsync(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'localshare-web-backup-confirmation-test-',
      );
      store = BackupProfileStore(rootDirectory: temporaryDirectory);
    });
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
    });

    final webSenderOpened = Completer<void>();
    final returnFromWebSender = Completer<void>();
    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: BackupPage(
            openStore: () async => store,
            isAndroidOverride: true,
            onOpenNativeTransfer: () async {},
            onOpenReceive: () async {},
            requestPermission: ({
              required includeImages,
              required includeVideos,
            }) async =>
                const BackupMediaPermissionResult(
              allowed: true,
              limited: false,
              permanentlyDenied: false,
            ),
            scanMedia: ({
              required includeImages,
              required includeVideos,
              required onProgress,
            }) async {
              onProgress(2);
              return _twoItemScan();
            },
            scanNearbyDevices: (_) async {},
            nearbyDevicesOverride: const NearbyDevicesState(
              runningFavoriteScan: false,
              runningIps: {},
              devices: {},
            ),
            sourceDeviceFingerprint: () => 'phone-1',
            openWebSender: (_, files) async {
              expect(files, hasLength(2));
              webSenderOpened.complete();
              await returnFromWebSender.future;
            },
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text(LocalShareCopy.scanForChanges));
    await tester.tap(find.text(LocalShareCopy.scanForChanges));
    await _pumpUntilFound(tester, find.byKey(const Key('backup-web-send')));
    await tester.tap(find.byKey(const Key('backup-web-send')));
    await _pumpUntilComplete(tester, webSenderOpened);

    expect(find.text(LocalShareCopy.pendingComputerReceipt), findsOneWidget);
    expect(
      find.text(LocalShareCopy.pendingComputerReceiptDescription(2)),
      findsOneWidget,
    );
    expect(find.text(LocalShareCopy.pendingConfirmation), findsNothing);
    expect(find.text(LocalShareCopy.confirmSaved), findsNothing);

    returnFromWebSender.complete();
    await _pumpUntilFound(
      tester,
      find.text(LocalShareCopy.pendingConfirmation),
    );
    expect(find.text(LocalShareCopy.pendingComputerReceipt), findsNothing);
    expect(
      find.text(LocalShareCopy.pendingConfirmationDescription(2)),
      findsOneWidget,
    );
    expect(find.text(LocalShareCopy.confirmSaved), findsOneWidget);
    await _pumpUntilManualConfirmationEnabled(tester);

    final index = await tester.runAsync(store.loadIndex);
    final profile = index!.selectedProfile!;
    final pending = await tester.runAsync(
      () => store.loadPending(profile.id),
    );
    expect(pending, isNotNull);

    await tester.ensureVisible(find.text(LocalShareCopy.confirmSaved));
    await tester.tap(find.text(LocalShareCopy.confirmSaved));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(LocalShareCopy.confirmSavedTitle), findsOneWidget);
    _expectDetail(
      key: const Key('backup-confirm-target'),
      label: LocalShareCopy.confirmationTargetComputer,
      value: profile.displayName,
    );
    _expectDetail(
      key: const Key('backup-confirm-count'),
      label: LocalShareCopy.confirmationItemCount,
      value: LocalShareCopy.itemCount(pending!.itemCount),
    );
    _expectDetail(
      key: const Key('backup-confirm-size'),
      label: LocalShareCopy.confirmationTotalSize,
      value: pending.totalBytes.asReadableFileSize,
    );
  });

  testWidgets(
      'manual confirmation confirms only the selected items and keeps '
      'the rest pending', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    late Directory temporaryDirectory;
    late BackupProfileStore store;
    await tester.runAsync(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'localshare-per-file-confirmation-test-',
      );
      store = BackupProfileStore(rootDirectory: temporaryDirectory);
    });
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
    });

    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: BackupPage(
            openStore: () async => store,
            isAndroidOverride: true,
            onOpenNativeTransfer: () async {},
            onOpenReceive: () async {},
            requestPermission: ({
              required includeImages,
              required includeVideos,
            }) async =>
                const BackupMediaPermissionResult(
              allowed: true,
              limited: false,
              permanentlyDenied: false,
            ),
            scanMedia: ({
              required includeImages,
              required includeVideos,
              required onProgress,
            }) async {
              onProgress(2);
              return _twoItemScan();
            },
            scanNearbyDevices: (_) async {},
            nearbyDevicesOverride: const NearbyDevicesState(
              runningFavoriteScan: false,
              runningIps: {},
              devices: {},
            ),
            sourceDeviceFingerprint: () => 'phone-1',
            openWebSender: (_, files) async {
              expect(files, hasLength(2));
            },
          ),
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text(LocalShareCopy.scanForChanges));
    await tester.tap(find.text(LocalShareCopy.scanForChanges));
    await _pumpUntilFound(tester, find.byKey(const Key('backup-web-send')));
    await tester.tap(find.byKey(const Key('backup-web-send')));
    await _pumpUntilFound(
      tester,
      find.text(LocalShareCopy.pendingConfirmation),
    );
    await _pumpUntilManualConfirmationEnabled(tester);

    await tester.ensureVisible(find.text(LocalShareCopy.confirmSaved));
    await tester.tap(find.text(LocalShareCopy.confirmSaved));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // The dialog lists every pending item with a checkbox.
    expect(
      find.byKey(const Key('backup-confirm-item-external:1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('backup-confirm-item-external:2')),
      findsOneWidget,
    );
    expect(
      find.text(LocalShareCopy.confirmSelected(2)),
      findsOneWidget,
    );

    // Unchecking every item disables confirmation.
    await tester.tap(find.byKey(const Key('backup-confirm-select-all')));
    await tester.pump();
    final disabledButton = tester.widget<FilledButton>(
      find.byKey(const Key('backup-confirm-selected')),
    );
    expect(disabledButton.onPressed, isNull);

    // Re-select all, then uncheck only the first item.
    await tester.tap(find.byKey(const Key('backup-confirm-select-all')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('backup-confirm-item-external:1')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    expect(
      find.text(LocalShareCopy.confirmSelected(1)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('backup-confirm-selected')));
    await _pumpUntilFound(
      tester,
      find.text(LocalShareCopy.pendingConfirmationDescription(1)),
    );

    final index = await tester.runAsync(store.loadIndex);
    final profile = index!.selectedProfile!;
    final ledger = await tester.runAsync(
      () => store.loadConfirmedLedger(profile.id),
    );
    final pending = await tester.runAsync(
      () => store.loadPending(profile.id),
    );

    expect(ledger, hasLength(1));
    expect(ledger!.single.mediaKey, 'external:2');
    expect(pending, isNotNull);
    expect(pending!.itemCount, 1);
    expect(pending.items.single.snapshotItem.mediaKey, 'external:1');
    expect(
      find.text(LocalShareCopy.pendingConfirmationDescription(1)),
      findsOneWidget,
    );
  });
}

AndroidMediaCatalogScan _twoItemScan() {
  return AndroidMediaCatalogScan(const [
    android_channel.BackupMediaItem(
      mediaKey: 'external:1',
      contentUri: 'content://media/external/images/media/1',
      relativePath: 'DCIM/Camera/',
      displayName: 'one.jpg',
      sizeBytes: 1024,
      modifiedAtSeconds: 1,
      generationModified: 1,
      mimeType: 'image/jpeg',
    ),
    android_channel.BackupMediaItem(
      mediaKey: 'external:2',
      contentUri: 'content://media/external/video/media/2',
      relativePath: 'DCIM/Camera/',
      displayName: 'two.mp4',
      sizeBytes: 2048,
      modifiedAtSeconds: 2,
      generationModified: 2,
      mimeType: 'video/mp4',
    ),
  ]);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsWidgets);
}

Future<void> _pumpUntilComplete(
  WidgetTester tester,
  Completer<void> completer,
) async {
  for (var attempt = 0; attempt < 100 && !completer.isCompleted; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(completer.isCompleted, isTrue);
  await tester.pump();
}

Future<void> _pumpUntilManualConfirmationEnabled(WidgetTester tester) async {
  final label = find.text(LocalShareCopy.confirmSaved);
  for (var attempt = 0; attempt < 100; attempt++) {
    final button = find.ancestor(
      of: label,
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    if (button.evaluate().isNotEmpty && tester.widget<FilledButton>(button).onPressed != null) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for manual backup confirmation to become enabled.');
}

void _expectDetail({
  required Key key,
  required String label,
  required String value,
}) {
  final row = find.byKey(key);
  expect(row, findsOneWidget);
  expect(find.descendant(of: row, matching: find.text(label)), findsOneWidget);
  expect(find.descendant(of: row, matching: find.text(value)), findsOneWidget);
}
