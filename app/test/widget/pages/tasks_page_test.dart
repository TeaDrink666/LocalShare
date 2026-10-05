import 'package:common/model/file_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/features/tasks/transfer_task.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/tasks_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import '../../mocks.mocks.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());
  testWidgets('task detail closes without canceling and fits a narrow phone', (tester) async {
    final persistence = MockPersistenceService();
    when(persistence.getTaskConcurrency()).thenReturn(2);
    final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    final service = container.notifier(taskProvider);
    var canceled = false;
    service.put(TransferTask(
        id: 'task',
        kind: TransferTaskKind.send,
        peer: 'Desktop',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        stage: TransferTaskStage.running,
        files: const [
          {'id': 'file', 'name': 'project/lib/main.dart', 'size': 100, 'status': 'sending'}
        ]));
    service.cancellations['task'] = () {
      canceled = true;
    };
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RefenaScope.withContainer(container: container, child: const MaterialApp(home: TasksPage())));
    expect(tester.takeException(), isNull);
    await tester.tap(find.textContaining('Desktop'));
    await tester.pumpAndSettle();
    expect(find.text('project/lib/main.dart'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(canceled, isFalse);
    expect(service.state.tasks['task']!.stage, TransferTaskStage.running);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tasks retains access to received files from old history', (tester) async {
    final persistence = MockPersistenceService();
    when(persistence.getTaskConcurrency()).thenReturn(2);
    when(persistence.getReceiveHistory()).thenReturn([
      ReceiveHistoryEntry(
          id: 'old',
          fileName: 'old-project.zip',
          fileType: FileType.other,
          path: null,
          savedToGallery: false,
          isMessage: false,
          fileSize: 100,
          senderAlias: 'My old PC',
          timestamp: DateTime.now().toUtc()),
    ]);
    await tester.pumpWidget(RefenaScope(
        overrides: [persistenceProvider.overrideWithValue(persistence)],
        child: MaterialApp(theme: getTheme(ColorMode.localsend, Brightness.light, null), home: const TasksPage())));
    await tester.tap(find.byKey(const Key('tasks-received-files')));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveHistoryPage), findsOneWidget);
    expect(find.text('old-project.zip'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('completed files expose open and show-in-folder actions', (tester) async {
    final persistence = MockPersistenceService();
    when(persistence.getTaskConcurrency()).thenReturn(2);
    final container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    container.notifier(taskProvider).put(const TransferTask(
            id: 'received',
            kind: TransferTaskKind.receive,
            peer: 'Phone',
            createdAt: 0,
            stage: TransferTaskStage.completed,
            files: [
              {'id': 'file', 'name': 'main.dart', 'size': 100, 'status': 'finished', 'path': 'C:/Downloads/task/main.dart'}
            ]));
    await tester.pumpWidget(RefenaScope.withContainer(container: container, child: const MaterialApp(home: TasksPage(taskId: 'received'))));
    await tester.tap(find.byKey(const ValueKey('task-file-actions-file')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
