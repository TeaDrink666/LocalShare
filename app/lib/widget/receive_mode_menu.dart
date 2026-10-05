import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum ReceiveMode { manual, favorites, all }

extension ReceiveModeLabel on ReceiveMode {
  String get label => switch (this) {
        ReceiveMode.manual => LocalShareCopy.isChinese ? '手动确认' : 'Ask every time',
        ReceiveMode.favorites => LocalShareCopy.isChinese ? '自动接收收藏设备' : 'Auto-accept favorites',
        ReceiveMode.all => LocalShareCopy.isChinese ? '自动接收所有设备' : 'Auto-accept everyone',
      };
}

ReceiveMode receiveMode(ReceiveTabVm vm) => vm.quickSaveSettings
    ? ReceiveMode.all
    : vm.quickSaveFromFavoritesSettings
        ? ReceiveMode.favorites
        : ReceiveMode.manual;

Future<void> setReceiveMode(BuildContext context, ReceiveTabVm vm, ReceiveMode mode) async {
  if (receiveMode(vm) == mode) return;
  // Turn off the other automatic mode first so the options stay exclusive.
  if (mode != ReceiveMode.all && vm.quickSaveSettings) {
    await vm.onSetQuickSave(context, false);
  }
  if (!context.mounted) return;
  if (mode != ReceiveMode.favorites && vm.quickSaveFromFavoritesSettings) {
    await vm.onSetQuickSaveFromFavorites(context, false);
  }
  if (!context.mounted) return;
  if (mode == ReceiveMode.all) {
    await vm.onSetQuickSave(context, true);
  } else if (mode == ReceiveMode.favorites) {
    await vm.onSetQuickSaveFromFavorites(context, true);
  }
}

class ReceiveModeMenu extends StatelessWidget {
  const ReceiveModeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(receiveTabVmProvider);
    return PopupMenuButton<ReceiveMode>(
      key: const Key('receive-mode-menu'),
      tooltip: LocalShareCopy.isChinese ? '接收方式' : 'Receiving mode',
      initialValue: receiveMode(vm),
      onSelected: (mode) async => setReceiveMode(context, vm, mode),
      itemBuilder: (_) => ReceiveMode.values
          .map((mode) => CheckedPopupMenuItem(
                value: mode,
                checked: mode == receiveMode(vm),
                child: Text(mode.label),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.download_rounded, size: 16),
          const SizedBox(width: 6),
          Flexible(child: Text(receiveMode(vm).label)),
          const Icon(Icons.expand_more_rounded, size: 18),
        ]),
      ),
    );
  }
}
