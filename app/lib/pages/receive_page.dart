import 'dart:async';

import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/receive_options_page.dart';
import 'package:localsend_app/pages/receive_page_controller.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/selection/selected_receiving_files_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/taskbar_helper.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> with Refena {
  @override
  void dispose() {
    super.dispose();
    unawaited(TaskbarHelper.clearProgressBar());
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(
      receivePageControllerProvider,
      listener: (prev, next) {
        if (prev.status != next.status) {
          // ignore: discarded_futures
          TaskbarHelper.visualizeStatus(next.status);
        }
      },
    );

    if (vm.status == null && vm.message == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final favorite = ref.watch(
      favoritesProvider.select((state) => state.findDevice(vm.sender)),
    );
    final senderName = favorite?.alias ?? vm.sender.alias;

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: LocalSharePageBackground(
          child: CustomScrollView(
            slivers: [
              SliverSafeArea(
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PageHeading(message: vm.message, isLink: vm.isLink),
                            const SizedBox(height: 18),
                            _SenderCard(
                              vm: vm,
                              senderName: senderName,
                            ),
                            const SizedBox(height: 16),
                            _RequestCard(vm: vm),
                            const SizedBox(height: 16),
                            _Actions(vm),
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
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.message, required this.isLink});

  final String? message;
  final bool isLink;

  @override
  Widget build(BuildContext context) {
    final title = switch ((message != null, isLink)) {
      (true, true) => _ReceiveRequestCopy.linkTitle,
      (true, false) => _ReceiveRequestCopy.messageTitle,
      _ => _ReceiveRequestCopy.filesTitle,
    };
    final icon = switch ((message != null, isLink)) {
      (true, true) => Icons.link_rounded,
      (true, false) => Icons.chat_bubble_outline_rounded,
      _ => Icons.download_rounded,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                _ReceiveRequestCopy.pageSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SenderCard extends StatelessWidget {
  const _SenderCard({required this.vm, required this.senderName});

  final ReceivePageVm vm;
  final String senderName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LocalShareSurface(
      style: LocalShareSurfaceStyle.accent,
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _ReceiveRequestCopy.fromDevice,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimary.withOpacity(0.78),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                senderName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (vm.showSenderInfo) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SenderBadge(
                      label: vm.showFullIp ? vm.sender.ip : '#${vm.sender.ip.visualId}',
                      onTap: () => context.redux(receivePageControllerProvider).dispatch(SetShowFullIpAction(!vm.showFullIp)),
                    ),
                    if (vm.sender.deviceModel != null) _SenderBadge(label: vm.sender.deviceModel!),
                  ],
                ),
              ],
            ],
          );
          final deviceIcon = Container(
            width: compact ? 58 : 76,
            height: compact ? 58 : 76,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(compact ? 18 : 24),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Icon(
              vm.sender.deviceType.icon,
              color: scheme.onPrimary,
              size: compact ? 30 : 38,
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [deviceIcon, const SizedBox(height: 18), identity],
            );
          }
          return Row(
            children: [
              deviceIcon,
              const SizedBox(width: 20),
              Expanded(child: identity),
            ],
          );
        },
      ),
    );
  }
}

class _SenderBadge extends StatelessWidget {
  const _SenderBadge({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.vm});

  final ReceivePageVm vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedFiles = context.watch(selectedReceivingFilesProvider);

    return LocalShareCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                vm.message != null ? (vm.isLink ? Icons.language_rounded : Icons.notes_rounded) : Icons.folder_copy_outlined,
                color: scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  vm.message != null
                      ? (vm.isLink ? t.receivePage.subTitleLink : t.receivePage.subTitleMessage)
                      : t.receivePage.subTitle(n: vm.fileCount),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (vm.message != null)
            Container(
              constraints: const BoxConstraints(minHeight: 96, maxHeight: 240),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.52),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  vm.message!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withOpacity(0.56),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.fact_check_outlined, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _ReceiveRequestCopy.selectedSummary(
                        selectedFiles.length,
                        vm.fileCount,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 19, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _ReceiveRequestCopy.securityHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions(this.vm);

  final ReceivePageVm vm;

  @override
  Widget build(BuildContext context) {
    final selectedFiles = context.watch(selectedReceivingFilesProvider);
    final scheme = Theme.of(context).colorScheme;

    if (vm.message != null) {
      return LocalShareCard(
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                vm.onAccept();
                context.pop();
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(t.general.close),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                unawaited(
                  Clipboard.setData(ClipboardData(text: vm.message!)),
                );
                if (checkPlatformIsDesktop()) {
                  context.showSnackBar(t.general.copiedToClipboard);
                }
                vm.onAccept();
                context.pop();
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(t.general.copy),
            ),
            if (vm.isLink)
              FilledButton.icon(
                onPressed: () {
                  // ignore: discarded_futures
                  launchUrl(
                    Uri.parse(vm.message!),
                    mode: LaunchMode.externalApplication,
                  );
                  vm.onAccept();
                  context.pop();
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(t.general.open),
              ),
          ],
        ),
      );
    }

    if (vm.status == SessionStatus.canceledBySender) {
      return LocalShareCard(
        child: Column(
          children: [
            Icon(Icons.cancel_outlined, color: scheme.error, size: 34),
            const SizedBox(height: 10),
            Text(
              t.receivePage.canceled,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.error,
                  ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                vm.onClose();
                context.pop();
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(t.general.close),
            ),
          ],
        ),
      );
    }

    return LocalShareCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520 || MediaQuery.textScalerOf(context).scale(16) > 20;
          final options = OutlinedButton.icon(
            onPressed: () async {
              await context.push(() => const ReceiveOptionsPage());
            },
            icon: const Icon(Icons.tune_rounded),
            label: Text(t.receiveOptionsPage.title),
          );
          final decisions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () {
                  vm.onDecline();
                  context.pop();
                },
                icon: const Icon(Icons.close_rounded),
                label: Text(t.general.decline),
              ),
              FilledButton.icon(
                onPressed: selectedFiles.isEmpty ? null : vm.onAccept,
                icon: const Icon(Icons.download_done_rounded),
                label: Text(t.general.accept),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                options,
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: decisions,
                ),
              ],
            );
          }
          return Row(
            children: [
              options,
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: decisions,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

abstract final class _ReceiveRequestCopy {
  static bool get _zh => LocalShareCopy.isChinese;

  static String get filesTitle => _zh ? '收到文件请求' : 'Incoming file request';
  static String get messageTitle => _zh ? '收到文字消息' : 'Incoming message';
  static String get linkTitle => _zh ? '收到网页链接' : 'Incoming link';
  static String get pageSubtitle => _zh ? '先核对发送设备和内容，再决定是否接收。' : 'Check the sender and content before approving.';
  static String get fromDevice => _zh ? '来自设备' : 'From device';
  static String get securityHint =>
      _zh ? '未经你确认，文件不会写入当前设备。传输只在局域网内进行。' : 'Files are not saved without your approval. The transfer stays on your LAN.';
  static String selectedSummary(int selected, int total) =>
      _zh ? '已选择 $selected / $total 项。你可以在接收选项中查看、取消或重命名文件。' : '$selected of $total selected. Open receive options to review, skip, or rename files.';
}
