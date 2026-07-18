import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/backup/data/android_media_catalog.dart';
import 'package:localsend_app/features/backup/data/backup_profile_store.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/pages/backup/backup_page.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart'
    as android_channel;
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  testWidgets(
    'returning from link transfer keeps backup actions available',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      late Directory temporaryDirectory;
      late BackupProfileStore store;
      await tester.runAsync(() async {
        temporaryDirectory = await Directory.systemTemp.createTemp(
          'localshare-backup-resend-test-',
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

      var webOpenCount = 0;
      await tester.pumpWidget(
        RefenaScope(
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: child!,
            ),
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
                onProgress(1);
                return AndroidMediaCatalogScan(const [
                  android_channel.BackupMediaItem(
                    mediaKey: 'external_primary:1',
                    contentUri: 'content://media/external/images/media/1',
                    relativePath: 'DCIM/Camera/',
                    displayName: 'photo.jpg',
                    sizeBytes: 2048,
                    modifiedAtSeconds: 10,
                    generationModified: 1,
                    mimeType: 'image/jpeg',
                  ),
                ]);
              },
              scanNearbyDevices: (_) async {},
              nearbyDevicesOverride: const NearbyDevicesState(
                runningFavoriteScan: false,
                runningIps: {},
                devices: {},
              ),
              sourceDeviceFingerprint: () => 'phone-test',
              openWebSender: (_, files) async {
                expect(files, hasLength(1));
                webOpenCount++;
              },
            ),
          ),
        ),
      );

      await _pumpUntilFound(
        tester,
        find.text(LocalShareCopy.scanForChanges),
      );
      final scanButton = find.text(LocalShareCopy.scanForChanges);
      await tester.ensureVisible(scanButton);
      await tester.tap(scanButton);
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('backup-web-send')),
      );

      await _tapWebSend(tester);
      await _pumpUntilFound(
        tester,
        find.text(LocalShareCopy.pendingConfirmation),
      );
      await _pumpUntilWebSendEnabled(tester);
      expect(webOpenCount, 1);
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const Key('backup-web-send')),
            )
            .onTap,
        isNotNull,
      );

      await _tapWebSend(tester);
      await _pumpUntilWebSendEnabled(tester);
      expect(webOpenCount, 2);
      expect(tester.takeException(), isNull);

      final index = await tester.runAsync(store.loadIndex);
      final pending = await tester.runAsync(
        () => store.loadPending(index!.selectedProfile!.id),
      );
      expect(pending, isNotNull);
      expect(pending!.itemCount, 1);
    },
  );

  testWidgets('embedded backup tab keeps its scanned plan when switching tabs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    late Directory temporaryDirectory;
    late BackupProfileStore store;
    await tester.runAsync(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'localshare-backup-keepalive-test-',
      );
      store = BackupProfileStore(rootDirectory: temporaryDirectory);
    });
    final pageController = PageController();
    addTearDown(() async {
      pageController.dispose();
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
    });

    var scanCount = 0;
    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                BackupPage(
                  embedded: true,
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
                    scanCount++;
                    onProgress(1);
                    return _onePhotoScan();
                  },
                  scanNearbyDevices: (_) async {},
                  nearbyDevicesOverride: const NearbyDevicesState(
                    runningFavoriteScan: false,
                    runningIps: {},
                    devices: {},
                  ),
                ),
                const Center(child: Text('Other tab')),
              ],
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFound(
      tester,
      find.text(LocalShareCopy.scanForChanges),
    );
    expect(find.byKey(const Key('backup-setup-card')), findsOneWidget);
    expect(find.text(LocalShareCopy.backupPageTitle), findsNothing);
    expect(find.text(LocalShareCopy.backupPageSubtitle), findsNothing);
    final scanButton = find.text(LocalShareCopy.scanForChanges);
    await tester.ensureVisible(scanButton);
    await tester.tap(scanButton);
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('backup-web-send')),
    );
    final nearbySection = find.byKey(const Key('backup-nearby-section'));
    final webSend = find.byKey(const Key('backup-web-send'));
    expect(nearbySection, findsOneWidget);
    expect(
      tester.getTopLeft(nearbySection).dy,
      lessThan(tester.getTopLeft(webSend).dy),
    );
    expect(scanCount, 1);

    pageController.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(find.text('Other tab'), findsOneWidget);

    pageController.jumpToPage(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-web-send')), findsOneWidget);
    expect(scanCount, 1);
    expect(tester.takeException(), isNull);
  });
}

AndroidMediaCatalogScan _onePhotoScan() {
  return AndroidMediaCatalogScan(const [
    android_channel.BackupMediaItem(
      mediaKey: 'external_primary:1',
      contentUri: 'content://media/external/images/media/1',
      relativePath: 'DCIM/Camera/',
      displayName: 'photo.jpg',
      sizeBytes: 2048,
      modifiedAtSeconds: 10,
      generationModified: 1,
      mimeType: 'image/jpeg',
    ),
  ]);
}

Future<void> _tapWebSend(WidgetTester tester) async {
  final entry = find.byKey(const Key('backup-web-send'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntilWebSendEnabled(WidgetTester tester) async {
  final entry = find.byKey(const Key('backup-web-send'));
  for (var attempt = 0; attempt < 100; attempt++) {
    if (entry.evaluate().isNotEmpty &&
        tester.widget<InkWell>(entry).onTap != null) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for the backup link action to become enabled.');
}
