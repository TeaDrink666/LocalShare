import 'package:flutter/services.dart';
import 'package:localsend_app/util/native/platform_check.dart';

const _transferChannel = MethodChannel(
  'org.localsend.localsend_app/localsend',
);

int _activeTransfers = 0;

/// Ref-counted Android foreground service helper for long transfers.
///
/// Starting a transfer increments the counter and (on the first transfer)
/// launches the foreground service so the process survives screen-off and
/// backgrounding. [stopTransferForegroundService] decrements the counter and
/// stops the service only when the last transfer ends.
Future<void> startTransferForegroundService() async {
  if (!checkPlatform([TargetPlatform.android])) {
    return;
  }
  _activeTransfers++;
  if (_activeTransfers == 1) {
    try {
      await _transferChannel.invokeMethod('startTransferService');
    } catch (_) {
      // The foreground service is best-effort; a failure must never break a
      // file transfer.
    }
  }
}

Future<void> stopTransferForegroundService() async {
  if (!checkPlatform([TargetPlatform.android])) {
    return;
  }
  if (_activeTransfers == 0) {
    return;
  }
  _activeTransfers--;
  if (_activeTransfers == 0) {
    try {
      await _transferChannel.invokeMethod('stopTransferService');
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
