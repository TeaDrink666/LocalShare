import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/localshare_design/localshare_page_background.dart';
import 'package:refena_flutter/refena_flutter.dart';

class WebReceivePage extends StatelessWidget {
  const WebReceivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final serverState = context.watch(serverProvider);
    final localIps = context.watch(localIpProvider).localIps;
    final scheme = Theme.of(context).colorScheme;

    final urls = serverState == null
        ? const <String>[]
        : localIps
            .map((ip) =>
                '${serverState.https ? 'https' : 'http'}://$ip:${serverState.port}/web-receive')
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(LocalShareCopy.webReceiveTitle)),
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
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [scheme.tertiary, scheme.primary],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.tertiary.withOpacity(0.2),
                            blurRadius: 28,
                            offset: const Offset(0, 13),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 8,
                                        height: 8,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                              color: Color(0xffa7f3d0),
                                              shape: BoxShape.circle),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        LocalShareCopy.waitingForBrowser,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  LocalShareCopy.webReceiveTitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  LocalShareCopy.webReceiveSubtitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                          color: Colors.white.withOpacity(0.8)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.move_to_inbox_rounded,
                                color: Colors.white, size: 35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: scheme.outlineVariant.withOpacity(0.58)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (urls.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Column(
                                children: [
                                  Icon(Icons.wifi_off_rounded,
                                      size: 42, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 12),
                                  Text(LocalShareCopy.offline,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
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
                              Icon(Icons.verified_user_outlined,
                                  size: 20, color: scheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  LocalShareCopy.webReceiveSecurity,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          if (serverState?.https == true) ...[
                            const SizedBox(height: 12),
                            Text(
                              t.webSharePage.encryptionHint.replaceAll(
                                  'LocalSend', LocalShareCopy.appName),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.error),
                            ),
                          ],
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
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: scheme.surface, borderRadius: BorderRadius.circular(13)),
            child: Icon(Icons.link_rounded, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              url,
              maxLines: 2,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: t.general.copy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.general.copiedToClipboard)));
              }
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: t.dialogs.qr.title,
            onPressed: () async {
              await showDialog(
                  context: context,
                  builder: (_) => QrDialog(data: url, label: url));
            },
            icon: const Icon(Icons.qr_code_rounded),
          ),
        ],
      ),
    );
  }
}
