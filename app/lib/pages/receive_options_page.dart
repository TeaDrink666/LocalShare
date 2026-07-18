import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/selection/selected_receiving_files_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/file_name_input_dialog.dart';
import 'package:localsend_app/widget/dialogs/quick_actions_dialog.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';

class ReceiveOptionsPage extends StatelessWidget {
  const ReceiveOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final session = ref.watch(serverProvider.select((state) => state?.session));
    if (session == null) {
      return const Scaffold(body: SizedBox());
    }
    final selection = ref.watch(selectedReceivingFilesProvider);
    final allFiles = session.files.values.toList();
    final selectedSize = allFiles
        .where((file) => selection.containsKey(file.file.id))
        .fold<int>(0, (sum, file) => sum + file.file.size);

    return Scaffold(
      appBar: AppBar(title: Text(_OptionsCopy.pageTitle)),
      body: LocalSharePageBackground(
        child: ResponsiveListView(
          maxWidth: 920,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          tabletPadding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
          children: [
            _OptionsSummary(
              selected: selection.length,
              total: allFiles.length,
              selectedSize: selectedSize,
            ),
            const SizedBox(height: 16),
            _DestinationCard(
              destination: checkPlatformWithFileSystem()
                  ? session.destinationDirectory
                  : t.receiveOptionsPage.appDirectory,
              onChange: checkPlatformWithFileSystem()
                  ? () async {
                      final directory = await pickDirectoryPath();
                      if (directory != null) {
                        ref
                            .notifier(serverProvider)
                            .setSessionDestinationDir(directory);
                      }
                    }
                  : null,
            ),
            if (checkPlatformWithGallery()) ...[
              const SizedBox(height: 16),
              _GalleryCard(
                enabled: session.saveToGallery,
                containsDirectories: session.containsDirectories,
                onChanged: (enabled) => ref
                    .notifier(serverProvider)
                    .setSessionSaveToGallery(enabled),
              ),
            ],
            const SizedBox(height: 20),
            _FilesHeader(
              onQuickActions: () async {
                await showDialog(
                  context: context,
                  builder: (_) => const QuickActionsDialog(),
                );
              },
              onReset: () => ref
                  .notifier(selectedReceivingFilesProvider)
                  .setFiles(allFiles.map((file) => file.file).toList()),
            ),
            const SizedBox(height: 10),
            ...allFiles.map(
              (file) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReceivingFileCard(
                  icon: file.file.fileType.icon,
                  originalName: file.file.fileName,
                  selectedName: selection[file.file.id],
                  size: file.file.size.asReadableFileSize,
                  onToggle: (selected) {
                    if (selected) {
                      ref
                          .notifier(selectedReceivingFilesProvider)
                          .select(file.file);
                    } else {
                      ref
                          .notifier(selectedReceivingFilesProvider)
                          .unselect(file.file.id);
                    }
                  },
                  onRename: selection[file.file.id] == null
                      ? null
                      : () async {
                          final result = await showDialog<String>(
                            context: context,
                            builder: (_) => FileNameInputDialog(
                              originalName: file.file.fileName,
                              initialName: selection[file.file.id]!,
                            ),
                          );
                          if (result != null) {
                            ref
                                .notifier(selectedReceivingFilesProvider)
                                .rename(file.file.id, result);
                          }
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionsSummary extends StatelessWidget {
  const _OptionsSummary({
    required this.selected,
    required this.total,
    required this.selectedSize,
  });

  final int selected;
  final int total;
  final int selectedSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LocalShareSurface(
      style: LocalShareSurfaceStyle.tinted,
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.surface.withOpacity(0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.fact_check_outlined, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _OptionsCopy.summary(selected, total),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _OptionsCopy.selectedSize(selectedSize.asReadableFileSize),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination, required this.onChange});

  final String destination;
  final Future<void> Function()? onChange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LocalShareSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.folder_copy_outlined,
            title: _OptionsCopy.destination,
            subtitle: _OptionsCopy.destinationSubtitle,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.52),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destination,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (onChange != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _OptionsCopy.changeDestination,
                    onPressed: onChange,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.enabled,
    required this.containsDirectories,
    required this.onChanged,
  });

  final bool enabled;
  final bool containsDirectories;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LocalShareSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.photo_library_outlined,
                  color: scheme.onPrimaryContainer),
            ),
            title: Text(_OptionsCopy.saveToGallery),
            subtitle: Text(_OptionsCopy.saveToGallerySubtitle),
            value: enabled,
            onChanged: onChanged,
          ),
          if (containsDirectories && !enabled)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.52),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                t.receiveOptionsPage.saveToGalleryOff,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilesHeader extends StatelessWidget {
  const _FilesHeader({required this.onQuickActions, required this.onReset});

  final Future<void> Function() onQuickActions;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onQuickActions,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(_OptionsCopy.quickActions),
            ),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.undo_rounded),
              label: Text(t.general.reset),
            ),
          ],
        );
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle(
                icon: Icons.list_alt_rounded,
                title: _OptionsCopy.files,
                subtitle: _OptionsCopy.filesSubtitle,
              ),
              const SizedBox(height: 12),
              Align(alignment: AlignmentDirectional.centerEnd, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _SectionTitle(
                icon: Icons.list_alt_rounded,
                title: _OptionsCopy.files,
                subtitle: _OptionsCopy.filesSubtitle,
              ),
            ),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceivingFileCard extends StatelessWidget {
  const _ReceivingFileCard({
    required this.icon,
    required this.originalName,
    required this.selectedName,
    required this.size,
    required this.onToggle,
    required this.onRename,
  });

  final IconData icon;
  final String originalName;
  final String? selectedName;
  final String size;
  final ValueChanged<bool> onToggle;
  final Future<void> Function()? onRename;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = selectedName != null;
    final renamed = selected && selectedName != originalName;
    final statusColor = !selected
        ? scheme.onSurfaceVariant
        : renamed
            ? scheme.warning
            : context.localShareDesign.success;
    final status = !selected
        ? t.general.skipped
        : renamed
            ? t.general.renamed
            : t.general.unchanged;

    return LocalShareSurface(
      style: selected
          ? LocalShareSurfaceStyle.standard
          : LocalShareSurfaceStyle.subtle,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedName ?? originalName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '$status · $size',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          if (onRename != null)
            IconButton(
              tooltip: _OptionsCopy.rename,
              onPressed: onRename,
              icon: const Icon(Icons.edit_outlined),
            ),
          Checkbox(
            value: selected,
            onChanged: (value) => onToggle(value == true),
          ),
        ],
      ),
    );
  }
}

abstract final class _OptionsCopy {
  static bool get _zh => LocalShareCopy.isChinese;

  static String get pageTitle => _zh ? '接收选项' : 'Receive options';
  static String summary(int selected, int total) =>
      _zh ? '将接收 $selected / $total 项' : '$selected of $total items selected';
  static String selectedSize(String size) =>
      _zh ? '预计保存 $size' : 'Estimated save size $size';
  static String get destination => _zh ? '保存位置' : 'Save location';
  static String get destinationSubtitle =>
      _zh ? '本次接收的文件将写入这里' : 'Files from this transfer are saved here';
  static String get changeDestination => _zh ? '更改保存位置' : 'Change location';
  static String get saveToGallery => _zh ? '保存到系统相册' : 'Save to gallery';
  static String get saveToGallerySubtitle => _zh
      ? '照片和视频接收完成后可在相册中查看'
      : 'Show received photos and videos in the gallery';
  static String get files => _zh ? '本次文件' : 'Files';
  static String get filesSubtitle =>
      _zh ? '选择、跳过或重命名要接收的内容' : 'Select, skip, or rename incoming items';
  static String get quickActions => _zh ? '批量选择' : 'Quick actions';
  static String get rename => _zh ? '重命名' : 'Rename';
}
