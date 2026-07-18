import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:test/test.dart';

void main() {
  test('canceling a waiting session reaches its prepare request exactly once',
      () {
    final registry = PrepareRequestCancelRegistry();
    var cancelCount = 0;

    registry.register('session-1', () => cancelCount++);
    expect(registry.activeCount, 1);

    registry.cancel('session-1');
    registry.cancel('session-1');

    expect(cancelCount, 1);
    expect(registry.activeCount, 0);
  });

  test('finishing a prepare request removes it without canceling', () {
    final registry = PrepareRequestCancelRegistry();
    var canceled = false;

    registry.register('session-1', () => canceled = true);
    registry.finish('session-1');

    expect(canceled, isFalse);
    expect(registry.activeCount, 0);
  });

  test('clearing sessions cancels every outstanding prepare request', () {
    final registry = PrepareRequestCancelRegistry();
    final canceled = <String>[];
    registry
      ..register('session-1', () => canceled.add('session-1'))
      ..register('session-2', () => canceled.add('session-2'))
      ..cancelAll();

    expect(canceled, unorderedEquals(['session-1', 'session-2']));
    expect(registry.activeCount, 0);
  });
}
