import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';

/// Keeps a backup page visible while its durable state is being updated.
///
/// Leaving during this short window can make a completed confirmation look as
/// though it was canceled, even though the write continues in the background.
class BackupSavingPopScope extends StatelessWidget {
  const BackupSavingPopScope({
    required this.saving,
    required this.child,
    super.key,
  });

  final bool saving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && saving) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(LocalShareCopy.savingBackupState)),
            );
        }
      },
      child: child,
    );
  }
}
