import 'package:localsend_app/features/tasks/task_queue.dart';
import 'package:test/test.dart';

void main() {
  test('two transfers run and the third waits for a released slot', () async {
    final queue = TransferTaskQueue();
    expect(await queue.acquire('one'), isTrue);
    expect(await queue.acquire('two'), isTrue);
    final third = queue.acquire('three');
    expect(queue.activeCount, 2);
    expect(queue.waitingCount, 1);
    queue.release('one');
    expect(await third, isTrue);
    expect(queue.activeCount, 2);
  });
  test('only one media sync runs while ordinary transfers bypass it', () async {
    final queue = TransferTaskQueue();
    expect(await queue.acquire('media-one', media: true), isTrue);
    final nextMedia = queue.acquire('media-two', media: true);
    expect(await queue.acquire('send'), isTrue);
    expect(queue.waitingCount, 1);
    queue.release('media-one');
    expect(await nextMedia, isTrue);
    expect(queue.activeCount, 2);
  });
  test('lowering the limit keeps running tasks and gates new tasks', () async {
    final queue = TransferTaskQueue();
    await queue.acquire('one');
    await queue.acquire('two');
    queue.limit = 1;
    final next = queue.acquire('three');
    queue.release('one');
    expect(queue.waitingCount, 1);
    queue.release('two');
    expect(await next, isTrue);
  });
  test('canceling a queued task completes its wait without admission', () async {
    final queue = TransferTaskQueue(limit: 1);
    await queue.acquire('one');
    final pending = queue.acquire('two');
    queue.release('two');
    expect(await pending, isFalse);
    expect(queue.activeCount, 1);
  });
}
