import 'dart:convert';

import 'package:common/model/file_type.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/ui/nav_bar_padding.dart';
import 'package:localsend_app/widget/dialogs/message_input_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class SelectedFilesPage extends StatelessWidget {
  const SelectedFilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final files = ref.watch(selectedSendingFilesProvider);
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);

    return Scaffold(
      appBar: AppBar(title: Text(_SelectedCopy.pageTitle)),
      body: LocalSharePageBackground(
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              top: false,
              sliver: SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  28 + getNavBarPadding(context),
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 920),
                          child: _SelectionSummary(
                            count: files.length,
                            totalSize: totalSize,
                            onClear: () {
                              ref
                                  .redux(selectedSendingFilesProvider)
                                  .dispatch(ClearSelectionAction());
                              context.popUntilRoot();
                            },
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    if (files.isEmpty)
                      SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 920),
                            child: _EmptySelection(
                              onClose: () => context.popUntilRoot(),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList.separated(
                        itemCount: files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 920),
                            child: _SelectedFileCard(
                              file: files[index],
                              onEditMessage: files[index].fileType ==
                                          FileType.text &&
                                      files[index].bytes != null
                                  ? () async {
                                      final message = _messageOf(files[index])!;
                                      final result = await showDialog<String>(
                                        context: context,
                                        builder: (_) => MessageInputDialog(
                                          initialText: message,
                                        ),
                                      );
                                      if (result != null) {
                                        ref
                                            .redux(selectedSendingFilesProvider)
                                            .dispatch(UpdateMessageAction(
                                              message: result,
                                              index: index,
                                            ));
                                      }
                                    }
                                  : null,
                              onRemove: () {
                                final currentCount = ref
                                    .read(selectedSendingFilesProvider)
                                    .length;
                                ref
                                    .redux(selectedSendingFilesProvider)
                                    .dispatch(RemoveSelectedFileAction(index));
                                if (currentCount == 1) {
                                  context.popUntilRoot();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.count,
    required this.totalSize,
    required this.onClear,
  });

  final int count;
  final int totalSize;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LocalShareSurface(
      style: LocalShareSurfaceStyle.tinted,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final details = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.surface.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.inventory_2_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 13),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _SelectedCopy.summaryTitle(count),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _SelectedCopy.totalSize(totalSize.asReadableFileSize),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final clearButton = OutlinedButton.icon(
            onPressed: count == 0 ? null : onClear,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(_SelectedCopy.clearAll),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 14),
                clearButton,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 18),
              clearButton,
            ],
          );
        },
      ),
    );
  }
}

class _SelectedFileCard extends StatelessWidget {
  const _SelectedFileCard({
    required this.file,
    required this.onEditMessage,
    required this.onRemove,
  });

  final CrossFile file;
  final Future<void> Function()? onEditMessage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = _messageOf(file);

    return LocalShareSurface(
      padding: EdgeInsets.zero,
      onTap: file.path == null
          ? null
          : () async => openFile(context, file.fileType, file.path!),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            SmartFileThumbnail.fromCrossFile(file),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message == null
                        ? file.name
                        : '“${message.replaceAll('\n', ' ')}”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.size.asReadableFileSize,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<_SelectedFileAction>(
              tooltip: _SelectedCopy.moreActions,
              onSelected: (action) async {
                switch (action) {
                  case _SelectedFileAction.edit:
                    await onEditMessage?.call();
                  case _SelectedFileAction.remove:
                    onRemove();
                }
              },
              itemBuilder: (context) => [
                if (onEditMessage != null)
                  PopupMenuItem(
                    value: _SelectedFileAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(_SelectedCopy.editMessage),
                    ),
                  ),
                PopupMenuItem(
                  value: _SelectedFileAction.remove,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      _SelectedCopy.remove,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySelection extends StatelessWidget {
  const _EmptySelection({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return LocalShareSurface(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(_SelectedCopy.emptyTitle,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            _SelectedCopy.emptyDescription,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(_SelectedCopy.backToSend),
          ),
        ],
      ),
    );
  }
}

enum _SelectedFileAction { edit, remove }

String? _messageOf(CrossFile file) {
  if (file.fileType != FileType.text || file.bytes == null) {
    return null;
  }
  return utf8.decode(file.bytes!);
}

abstract final class _SelectedCopy {
  static bool get _zh => LocalShareCopy.isChinese;

  static String get pageTitle => _zh ? '已选内容' : 'Selected items';
  static String summaryTitle(int count) =>
      _zh ? '已选择 $count 项' : '$count ${count == 1 ? 'item' : 'items'} selected';
  static String totalSize(String size) =>
      _zh ? '预计传输大小 $size' : 'Estimated transfer size $size';
  static String get clearAll => _zh ? '清空全部' : 'Clear all';
  static String get moreActions => _zh ? '更多操作' : 'More actions';
  static String get editMessage => _zh ? '编辑文字' : 'Edit text';
  static String get remove => _zh ? '从列表移除' : 'Remove from list';
  static String get emptyTitle => _zh ? '发送列表为空' : 'Nothing selected';
  static String get emptyDescription => _zh
      ? '返回发送页，选择文件、照片视频或文字。'
      : 'Return to Send and choose files, media, or text.';
  static String get backToSend => _zh ? '返回发送页' : 'Back to Send';
}
