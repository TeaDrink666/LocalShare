import 'dart:async';

import 'package:common/model/file_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/web_gateway/web_gateway_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:refena_flutter/refena_flutter.dart';

class WebReceivePage extends StatefulWidget {
  const WebReceivePage({super.key});

  @override
  State<WebReceivePage> createState() => _WebReceivePageState();
}

class _WebReceivePageState extends State<WebReceivePage> with Refena {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.notifier(webGatewayProvider).startWebReceive());
    });
  }

  Future<void> _stop() async {
    await ref.notifier(webGatewayProvider).stopWebReceive();
  }

  @override
  Widget build(BuildContext context) {
    final gatewayState = context.watch(webGatewayProvider);
    final localIps = context.watch(localIpProvider).localIps;
    final scheme = Theme.of(context).colorScheme;

    final urls =
        gatewayState == null ? const <String>[] : localIps.map((ip) => 'http://$ip:${gatewayState.port}/web-receive').toList(growable: false);

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(title: Text(LocalShareCopy.webReceiveTitle), actions: [
          IconButton(
              onPressed: _stop, tooltip: LocalShareCopy.isChinese ? '停止网页接收' : 'Stop web receiver', icon: const Icon(Icons.stop_circle_outlined))
        ]),
        body: LocalSharePageBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LocalShareHero(
                        badge: LocalShareHeroBadge(label: LocalShareCopy.waitingForBrowser, dotColor: const Color(0xffa7f3d0)),
                        title: LocalShareCopy.webReceiveTitle,
                        subtitle: LocalShareCopy.webReceiveSubtitle,
                        icon: Icons.move_to_inbox_rounded,
                      ),
                      const SizedBox(height: 20),
                      if (gatewayState?.receiveSession != null) ...[
                        _UploadSessionCard(
                          session: gatewayState!.receiveSession!,
                          onAccept: () => ref.notifier(webGatewayProvider).acceptWebReceiveRequest(),
                          onDecline: () => ref.notifier(webGatewayProvider).declineWebReceiveRequest(),
                        ),
                        const SizedBox(height: 20),
                      ],
                      LocalShareCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (urls.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 28),
                                child: Column(
                                  children: [
                                    Icon(Icons.wifi_off_rounded, size: 42, color: scheme.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(LocalShareCopy.offline, style: Theme.of(context).textTheme.titleMedium),
                                  ],
                                ),
                              )
                            else
                              ...urls.map((url) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _AddressCard(url: url),
                                  )),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.verified_user_outlined, size: 20, color: scheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    LocalShareCopy.webReceiveSecurity,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadSessionCard extends StatelessWidget {
  const _UploadSessionCard({
    required this.session,
    required this.onAccept,
    required this.onDecline,
  });

  final ReceiveSessionState session;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = session.responseHandler != null;
    final theme = Theme.of(context);
    final totalBytes = session.files.values.fold<int>(0, (sum, f) => sum + f.file.size);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pending ? scheme.tertiaryContainer.withOpacity(0.5) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LocalShareRadii.large),
        border: Border.all(
          color: (pending ? scheme.tertiary : scheme.outlineVariant).withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                pending ? Icons.notifications_active_outlined : Icons.cloud_download_outlined,
                color: pending ? scheme.tertiary : scheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending ? LocalShareCopy.webReceiveRequestTitle : LocalShareCopy.webReceiveProgressTitle,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${session.senderAlias} · ${session.sender.ip}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${LocalShareCopy.itemCount(session.files.length)} · '
                      '${totalBytes.asReadableFileSize}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pending) ...[
            const SizedBox(height: 12),
            Text(
              LocalShareCopy.webReceiveRequestHint,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('web-receive-decline'),
                  onPressed: onDecline,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(t.general.decline),
                ),
                FilledButton.icon(
                  key: const Key('web-receive-accept'),
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(t.general.accept),
                ),
              ],
            ),
          ] else
            _SessionProgress(session: session),
        ],
      ),
    );
  }
}

class _SessionProgress extends StatelessWidget {
  const _SessionProgress({required this.session});

  final ReceiveSessionState session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = context.watch(progressProvider);
    final files = session.files.values.toList(growable: false);
    final finishedCount = files.where((f) => f.status == FileStatus.finished).length;
    final failedCount = files.where((f) => f.status == FileStatus.failed).length;

    var totalProgress = 0.0;
    for (final file in files) {
      totalProgress += progress.getProgress(
        sessionId: session.sessionId,
        fileId: file.file.id,
      );
    }
    final fraction = files.isEmpty ? 0.0 : (totalProgress / files.length).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 8),
        Text(
          '${(fraction * 100).round()}% · '
          '${LocalShareCopy.itemCount(finishedCount)}'
          '${failedCount > 0 ? ' · ${LocalShareCopy.failedItemCount(failedCount)}' : ''}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  final String url;

  const _AddressCard({required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withOpacity(0.42),
        borderRadius: BorderRadius.circular(LocalShareRadii.large),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.link_rounded, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              url,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: t.general.copy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.general.copiedToClipboard)));
              }
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: t.dialogs.qr.title,
            onPressed: () async {
              await showDialog(context: context, builder: (_) => QrDialog(data: url, label: url));
            },
            icon: const Icon(Icons.qr_code_rounded),
          ),
        ],
      ),
    );
  }
}
