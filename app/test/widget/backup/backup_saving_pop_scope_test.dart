import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/backup/presentation/backup_saving_pop_scope.dart';

void main() {
  testWidgets('blocks user navigation while backup state is being saved', (
    tester,
  ) async {
    final saving = ValueNotifier<bool>(true);
    addTearDown(saving.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ValueListenableBuilder<bool>(
                      valueListenable: saving,
                      builder: (context, value, _) => BackupSavingPopScope(
                        saving: value,
                        child: const Scaffold(
                          body: Center(child: Text('backup operation')),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open backup'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open backup'));
    await tester.pumpAndSettle();
    expect(find.text('backup operation'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('backup operation'), findsOneWidget);
    expect(find.text(LocalShareCopy.savingBackupState), findsOneWidget);

    saving.value = false;
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('backup operation'), findsNothing);
    expect(find.text('open backup'), findsOneWidget);
  });
}
