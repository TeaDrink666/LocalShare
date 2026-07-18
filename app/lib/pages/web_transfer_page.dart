import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/pages/web_receive_page.dart';
import 'package:localsend_app/pages/web_send_page.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/localshare_design/localshare_page_background.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class WebTransferPage extends StatelessWidget {
  final Future<void> Function() onOpenNativeTransfer;

  const WebTransferPage({required this.onOpenNativeTransfer, super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final files = context.watch(selectedSendingFilesProvider);
    final scheme = Theme.of(context).colorScheme;
    final totalBytes = files.fold<int>(0, (sum, file) => sum + file.size);

    return Scaffold(
      appBar: AppBar(title: Text(LocalShareCopy.webPageTitle)),
      body: LocalSharePageBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PageIntro(
                      icon: Icons.language_rounded,
                      title: LocalShareCopy.webPageTitle,
                      subtitle: LocalShareCopy.webPageSubtitle,
                    ),
                    const SizedBox(height: 22),
                    _TransferSection(
                      icon: Icons.upload_file_rounded,
                      accent: scheme.primary,
                      title: LocalShareCopy.sendToBrowser,
                      description: LocalShareCopy.sendToBrowserDescription,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (files.isEmpty) ...[
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: FilePickerOption.getOptionsForPlatform()
                                  .map((option) {
                                return OutlinedButton.icon(
                                  onPressed: () async {
                                    await ref.global.dispatchAsync(
                                        PickFileAction(
                                            option: option, context: context));
                                  },
                                  icon: Icon(option.icon),
                                  label: Text(option.label),
                                );
                              }).toList(),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    scheme.primaryContainer.withOpacity(0.42),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: Icon(Icons.folder_copy_rounded,
                                        color: scheme.onPrimary),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(LocalShareCopy.selectedItems,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${LocalShareCopy.itemCount(files.length)}  ·  ${totalBytes.asReadableFileSize}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: LocalShareCopy.clearSelection,
                                    onPressed: () => ref
                                        .redux(selectedSendingFilesProvider)
                                        .dispatch(ClearSelectionAction()),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await onOpenNativeTransfer();
                                    if (context.mounted) {
                                      context.pop();
                                    }
                                  },
                                  icon: const Icon(Icons.devices_rounded),
                                  label: Text(LocalShareCopy.continueInClient),
                                ),
                                FilledButton.icon(
                                  onPressed: () async {
                                    await context
                                        .push(() => WebSendPage(files));
                                  },
                                  icon: const Icon(Icons.qr_code_rounded),
                                  label: Text(LocalShareCopy.createLink),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TransferSection(
                      icon: Icons.download_for_offline_outlined,
                      accent: scheme.tertiary,
                      title: LocalShareCopy.uploadFromBrowser,
                      description: LocalShareCopy.uploadFromBrowserDescription,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await context.push(() => const WebReceivePage());
                          },
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: Text(LocalShareCopy.openUploadPortal),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIntro extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PageIntro(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.tertiaryContainer.withOpacity(0.72)
          ],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: scheme.surface.withOpacity(0.74),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(icon, color: scheme.primary, size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferSection extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final Widget? child;

  const _TransferSection({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(description,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 20),
            child!,
          ],
        ],
      ),
    );
  }
}
