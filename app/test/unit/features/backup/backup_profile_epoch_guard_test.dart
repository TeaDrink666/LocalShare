import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/features/backup/presentation/backup_profile_epoch_guard.dart';

void main() {
  group('BackupProfileEpochGuard', () {
    test('accepts work for the captured profile', () {
      final guard = BackupProfileEpochGuard();
      final epoch = guard.capture();

      expect(
        guard.matches(
          epoch: epoch,
          profileId: 'computer-a',
          selectedProfileId: 'computer-a',
        ),
        isTrue,
      );
    });

    test('rejects a stale load after the profile changes', () {
      final guard = BackupProfileEpochGuard();
      final staleEpoch = guard.capture();

      guard.invalidate();

      expect(
        guard.matches(
          epoch: staleEpoch,
          profileId: 'computer-a',
          selectedProfileId: 'computer-b',
        ),
        isFalse,
      );
    });

    test('rejects stale work even when profile IDs match again', () {
      final guard = BackupProfileEpochGuard();
      final staleEpoch = guard.capture();

      guard.invalidate();

      expect(
        guard.matches(
          epoch: staleEpoch,
          profileId: 'computer-a',
          selectedProfileId: 'computer-a',
        ),
        isFalse,
      );
    });
  });
}
