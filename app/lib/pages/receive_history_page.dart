import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/pages/receive_page_controller.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/file_info_dialog.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:path/path.dart' as path;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _EntryOption {
  open,
  showInFolder,
  info,
  delete;

  String get label {
    return switch (this) {
      _EntryOption.open => t.receiveHistoryPage.entryActions.open,
      _EntryOption.showInFolder => t.receiveHistoryPage.entryActions.showInFolder,
      _EntryOption.info => t.receiveHistoryPage.entryActions.info,
      _EntryOption.delete => t.receiveHistoryPage.entryActions.deleteFromHistory,
    };
  }

  IconData get icon {
    return switch (this) {
      _EntryOption.open => Icons.open_in_new_rounded,
      _EntryOption.showInFolder => Icons.folder_open_rounded,
      _EntryOption.info => Icons.info_outline_rounded,
      _EntryOption.delete => Icons.delete_outline_rounded,
    };
  }
}

const _optionsAll = _EntryOption.values;
final _optionsWithoutOpen = [_EntryOption.info, _EntryOption.delete];

class ReceiveHistoryPage extends StatelessWidget {
  const ReceiveHistoryPage({super.key});

  Future<void> _openFile(
    BuildContext context,
    ReceiveHistoryEntry entry,
    Dispatcher<ReceiveHistoryService, List<ReceiveHistoryEntry>> dispatcher,
  ) async {
    if (entry.path != null) {
      await openFile(
        context,
        entry.fileType,
        entry.path!,
        onDeleteTap: () => dispatcher.dispatchAsync(RemoveHistoryEntryAction(entry.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = context.watch(receiveHistoryProvider);
    final totalBytes = entries.fold<int>(0, (sum, entry) => sum + entry.fileSize);

    return Scaffold(
      appBar: AppBar(
        title: Text(_HistoryCopy.pageTitle),
      ),
      body: LocalSharePageBackground(
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 48),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HistorySummary(
                            entryCount: entries.length,
                            totalBytes: totalBytes,
                            onOpenFolder: checkPlatform([TargetPlatform.iOS])
                                ? null
                                : () async {
                                    // ignore: use_build_context_synchronously
                                    final destination = context.read(settingsProvider).destination ?? await getDefaultDestinationDirectory();
                                    await openFolder(folderPath: destination);
                                  },
                            onClear: entries.isEmpty
                                ? null
                                : () async {
                                    final result = await showDialog(
                                      context: context,
                                      builder: (_) => const HistoryClearDialog(),
                                    );

                                    if (context.mounted && result == true) {
                                      await context.redux(receiveHistoryProvider).dispatchAsync(
                                            RemoveAllHistoryEntriesAction(),
                                          );
                                    }
                                  },
                          ),
                          const SizedBox(height: 20),
                          if (entries.isEmpty)
                            const _EmptyHistory()
                          else ...[
                            _HistorySectionHeading(count: entries.length),
                            const SizedBox(height: 10),
                            ...entries.map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _HistoryEntryCard(
                                  entry: entry,
                                  onTap: entry.path != null || entry.isMessage
                                      ? () async {
                                          if (entry.isMessage) {
                                            context
                                                .redux(
                                                  receivePageControllerProvider,
                                                )
                                                .dispatch(
                                                  InitReceivePageFromHistoryMessageAction(
                                                    entry: entry,
                                                  ),
                                                );
                                            // ignore: unawaited_futures
                                            context.push(
                                              () => const ReceivePage(),
                                            );
                                            return;
                                          }

                                          await _openFile(
                                            context,
                                            entry,
                                            context.redux(
                                              receiveHistoryProvider,
                                            ),
                                          );
                                        }
                                      : null,
                                  onSelected: (item) async {
                                    switch (item) {
                                      case _EntryOption.open:
                                        await _openFile(
                                          context,
                                          entry,
                                          context.redux(receiveHistoryProvider),
                                        );
                                        break;
                                      case _EntryOption.showInFolder:
                                        if (entry.path != null) {
                                          await openFolder(
                                            folderPath: File(entry.path!).parent.path,
                                            fileName: path.basename(entry.path!),
                                          );
                                        }
                                        break;
                                      case _EntryOption.info:
                                        // ignore: use_build_context_synchronously
                                        await showDialog(
                                          context: context,
                                          builder: (_) => FileInfoDialog(entry: entry),
                                        );
                                        break;
                                      case _EntryOption.delete:
                                        final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (dialogContext) => AlertDialog(
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              color: Theme.of(dialogContext).colorScheme.error,
                                              size: 32,
                                            ),
                                            title: Text(
                                              _HistoryCopy.deleteEntryTitle,
                                            ),
                                            content: Text(
                                              _HistoryCopy.deleteEntryMessage(entry.fileName),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(dialogContext).pop(false),
                                                child: Text(t.general.cancel),
                                              ),
                                              FilledButton(
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                                                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                                                ),
                                                onPressed: () => Navigator.of(dialogContext).pop(true),
                                                child: Text(t.general.delete),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true && context.mounted) {
                                          await context.redux(receiveHistoryProvider).dispatchAsync(
                                                RemoveHistoryEntryAction(entry.id),
                                              );
                                        }
                                        break;
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  final int entryCount;
  final int totalBytes;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onClear;

  const _HistorySummary({
    required this.entryCount,
    required this.totalBytes,
    required this.onOpenFolder,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.lerp(
              scheme.primaryContainer,
              scheme.tertiaryContainer,
              0.58,
            )!,
          ],
        ),
        borderRadius: BorderRadius.circular(LocalShareRadii.hero),
        border: Border.all(color: scheme.primary.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: scheme.surface.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(LocalShareRadii.medium),
                ),
                child: Icon(
                  Icons.history_rounded,
                  color: scheme.primary,
                  size: 27,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _HistoryCopy.summaryTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _HistoryCopy.summaryDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryMetric(
                icon: Icons.inventory_2_outlined,
                label: _HistoryCopy.itemCount(entryCount),
              ),
              _SummaryMetric(
                icon: Icons.data_usage_rounded,
                label: totalBytes.asReadableFileSize,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: onOpenFolder,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(_HistoryCopy.openFolder),
              ),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(_HistoryCopy.clearHistory),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryMetric({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _HistorySectionHeading extends StatelessWidget {
  final int count;

  const _HistorySectionHeading({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            _HistoryCopy.recentItems,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  final ReceiveHistoryEntry entry;
  final VoidCallback? onTap;
  final ValueChanged<_EntryOption> onSelected;

  const _HistoryEntryCard({
    required this.entry,
    required this.onTap,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final options = entry.path != null ? _optionsAll : _optionsWithoutOpen;

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.56)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withOpacity(0.56),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: FilePathThumbnail(
                  path: entry.path,
                  fileType: entry.fileType,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.fileName,
                      maxLines: entry.isMessage ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _MetadataPill(
                          icon: Icons.person_outline_rounded,
                          label: entry.senderAlias,
                        ),
                        _MetadataPill(
                          icon: Icons.schedule_rounded,
                          label: entry.timestampString,
                        ),
                        _MetadataPill(
                          icon: Icons.data_usage_rounded,
                          label: entry.fileSize.asReadableFileSize,
                        ),
                      ],
                    ),
                    if (entry.isMessage || entry.savedToGallery || entry.path == null) ...[
                      const SizedBox(height: 9),
                      _EntryState(entry: entry),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<_EntryOption>(
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                onSelected: onSelected,
                itemBuilder: (context) => options
                    .map(
                      (option) => PopupMenuItem<_EntryOption>(
                        value: option,
                        child: Row(
                          children: [
                            Icon(option.icon, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(option.label)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryState extends StatelessWidget {
  final ReceiveHistoryEntry entry;

  const _EntryState({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, color) = entry.isMessage
        ? (Icons.chat_bubble_outline_rounded, _HistoryCopy.message, scheme.primary)
        : entry.savedToGallery
            ? (Icons.photo_library_outlined, _HistoryCopy.savedToGallery, scheme.tertiary)
            : (Icons.link_off_rounded, _HistoryCopy.unavailable, scheme.error);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.56)),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inbox_outlined,
              size: 34,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _HistoryCopy.emptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _HistoryCopy.emptyDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _HistoryCopy {
  static bool get _zh => LocalShareCopy.isChinese;

  static String get pageTitle => _zh ? '接收历史' : 'Receive history';
  static String get summaryTitle => _zh ? '最近收到的内容' : 'Recently received';
  static String get summaryDescription =>
      _zh ? '查看通过 LocalShare 收到的文件和消息，或打开保存目录。' : 'Review files and messages received through LocalShare, or open the save folder.';
  static String itemCount(int count) => _zh ? '$count 条记录' : '$count ${count == 1 ? 'entry' : 'entries'}';
  static String get openFolder => _zh ? '打开保存目录' : 'Open folder';
  static String get clearHistory => _zh ? '清空历史' : 'Clear history';
  static String get recentItems => _zh ? '历史记录' : 'History';
  static String get emptyTitle => _zh ? '还没有接收记录' : 'No receive history yet';
  static String get emptyDescription => _zh ? '收到文件或消息后，它们会显示在这里。' : 'Files and messages you receive will appear here.';
  static String get message => _zh ? '文本消息' : 'Text message';
  static String get savedToGallery => _zh ? '已保存到相册' : 'Saved to gallery';
  static String get unavailable => _zh ? '文件已不可用' : 'File unavailable';
  static String get deleteEntryTitle => _zh ? '删除这条记录？' : 'Delete this entry?';
  static String deleteEntryMessage(String name) =>
      _zh ? '将从历史中移除“" + dollar + "{name}”。文件本身不会被删除。' : 'Remove “" + dollar + "{name}” from history. The file itself is not deleted.';
}
