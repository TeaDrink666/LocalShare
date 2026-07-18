/// Invalidates asynchronous backup-profile work when the active profile
/// changes.
final class BackupProfileEpochGuard {
  int _epoch = 0;

  int capture() => _epoch;

  int invalidate() => ++_epoch;

  bool owns(int epoch) => epoch == _epoch;

  bool matches({
    required int epoch,
    required String profileId,
    required String? selectedProfileId,
  }) =>
      owns(epoch) && profileId == selectedProfileId;
}
