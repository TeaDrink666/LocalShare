import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/backup/data/backup_profile_store.dart';
import 'package:localsend_app/pages/backup/backup_page.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  testWidgets('storage failure disables backup flow and retry recovers', (
    tester,
  ) async {
    final temporaryDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('localshare-backup-page-test-'),
    ))!;
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
    });

    final retryCompleter = Completer<BackupProfileStore>();
    var attempts = 0;
    Future<BackupProfileStore> openStore() {
      attempts++;
      if (attempts == 1) {
        return Future<BackupProfileStore>.error(
          const FileSystemException('storage offline'),
        );
      }
      return retryCompleter.future;
    }

    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: BackupPage(
            openStore: openStore,
            isAndroidOverride: true,
            onOpenNativeTransfer: () async {},
            onOpenReceive: () async {},
          ),
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.textContaining(LocalShareCopy.backupStorageUnavailable),
    );

    expect(attempts, 1);
    expect(
      find.textContaining(LocalShareCopy.backupStorageUnavailable),
      findsOneWidget,
    );
    expect(find.text(LocalShareCopy.retry), findsOneWidget);
    expect(find.text(LocalShareCopy.scanForChanges), findsNothing);

    await tester.tap(find.text(LocalShareCopy.retry));
    await tester.pump();

    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(LocalShareCopy.retry), findsNothing);
    expect(find.text(LocalShareCopy.scanForChanges), findsNothing);

    final store = BackupProfileStore(rootDirectory: temporaryDirectory);
    retryCompleter.complete(store);
    await _pumpUntilFound(tester, find.text(LocalShareCopy.scanForChanges));

    expect(find.text(LocalShareCopy.backupStorageUnavailable), findsNothing);
    expect(find.text(LocalShareCopy.retry), findsNothing);
    expect(find.text(LocalShareCopy.scanForChanges), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for ${finder.describeMatch(Plurality.one)}.');
}
