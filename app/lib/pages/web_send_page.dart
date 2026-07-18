import 'dart:async';

import 'package:common/util/sleep.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_session.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_app/widget/dialogs/qr_dialog.dart';
import 'package:localsend_app/widget/dialogs/zoom_dialog.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';
import 'package:localsend_app/widget/localshare_design/localshare_page_background.dart';
import 'package:localsend_app/widget/localshare_design/localshare_section_header.dart';
import 'package:localsend_app/widget/localshare_design/localshare_surface.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ServerState { initializing, running, error, stopping }

class WebSendPage extends StatefulWidget {
  final List<CrossFile> files;

  const WebSendPage(this.files);

  @override
  State<WebSendPage> createState() => _WebSendPageState();
}

class _WebSendPageState extends State<WebSendPage> with Refena {
  _ServerState _stateEnum = _ServerState.initializing;
  bool _encrypted = false;
  String? _initializedError;
  Future<void>? _initialization;
  int _operationGeneration = 0;
  bool _closing = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _beginInit(encrypted: false);
    });
  }

  void _beginInit({required bool encrypted}) {
    if (_closing || !mounted) {
      return;
    }
    unawaited(_initialization = _init(encrypted: encrypted));
  }

  Future<void> _init({required bool encrypted}) async {
    final operationGeneration = ++_operationGeneration;
    final settings = ref.read(settingsProvider);
    final (beforeAutoAccept, beforePin) = ref.read(serverProvider.select(
        (state) =>
            (state?.webSendState?.autoAccept, state?.webSendState?.pin)));
    setState(() {
      _stateEnum = _ServerState.initializing;
      _encrypted = encrypted;
      _initializedError = null;
    });
    await sleepAsync(500);
    if (_closing || operationGeneration != _operationGeneration) {
      return;
    }
    try {
      await ref.notifier(serverProvider).restartServer(
            alias: settings.alias,
            port: settings.port,
            https: _encrypted,
          );
      if (_closing || operationGeneration != _operationGeneration) {
        return;
      }
      await ref.notifier(serverProvider).initializeWebSend(widget.files);
      if (_closing || operationGeneration != _operationGeneration) {
        return;
      }
      if (beforeAutoAccept != null) {
        ref.notifier(serverProvider).setWebSendAutoAccept(beforeAutoAccept);
      }
      ref.notifier(serverProvider).setWebSendPin(beforePin);
      if (mounted) {
        setState(() {
          _stateEnum = _ServerState.running;
        });
      }
    } catch (e) {
      if (mounted && !_closing && operationGeneration == _operationGeneration) {
        setState(() {
          _stateEnum = _ServerState.error;
          _initializedError = e.toString();
        });
      }
    }
  }

  /// Web share uses unencrypted http, so we need to revert to the previous state.
  Future<void> _revertServerState() async {
    await ref.notifier(serverProvider).restartServerFromSettings();
  }

  Future<void> _requestClose() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _operationGeneration++;
    if (mounted) {
      setState(() {
        _stateEnum = _ServerState.stopping;
      });
    }

    try {
      await _initialization;
    } catch (_) {
      // The normal cleanup below still needs to restore the native server.
    }
    try {
      await _revertServerState();
    } catch (_) {
      // Exiting the page must remain possible even if server recovery fails.
    } finally {
      if (mounted) {
        setState(() {
          _allowPop = true;
        });
        await Future<void>.delayed(Duration.zero);
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestClose());
        }
      },
      canPop: _allowPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(copy.pageTitle),
        ),
        body: LocalSharePageBackground(
          child: Builder(
            builder: (context) {
              if (_stateEnum != _ServerState.running) {
                return _ServerStatusView(
                  state: _stateEnum,
                  error: _initializedError,
                  onRetry: () => _beginInit(encrypted: _encrypted),
                );
              }

              final serverState = context.watch(serverProvider);
              final webSendState = serverState?.webSendState;
              final localIps = context.watch(localIpProvider).localIps;
              if (serverState == null || webSendState == null) {
                return _ServerStatusView(
                  state: _ServerState.error,
                  error: copy.missingServerState,
                  onRetry: () => _beginInit(encrypted: _encrypted),
                );
              }

              final addresses = localIps.map((ip) {
                final url =
                    '${_encrypted ? 'https' : 'http'}://$ip:${serverState.port}';
                final urlWithPin = webSendState.pin == null
                    ? url
                    : '$url/?pin=${Uri.encodeQueryComponent(webSendState.pin!)}';
                return _ShareAddress(
                  displayUrl: url,
                  actionUrl: urlWithPin,
                );
              }).toList(growable: false);

              return _RunningWebSendView(
                addresses: addresses,
                sessions: webSendState.sessions.values.toList(growable: false),
                fileCount: widget.files.length,
                encrypted: _encrypted,
                autoAccept: webSendState.autoAccept,
                pin: webSendState.pin,
                onEncryptionChanged: (value) {
                  _beginInit(encrypted: value);
                },
                onAutoAcceptChanged: (value) {
                  ref.notifier(serverProvider).setWebSendAutoAccept(value);
                },
                onPinChanged: (value) async {
                  if (!value) {
                    ref.notifier(serverProvider).setWebSendPin(null);
                    return;
                  }
                  final newPin = await showDialog<String>(
                    context: context,
                    builder: (_) => const PinDialog(
                      obscureText: false,
                      generateRandom: true,
                    ),
                  );
                  if (newPin != null && newPin.isNotEmpty) {
                    ref.notifier(serverProvider).setWebSendPin(newPin);
                  }
                },
                onAccept: (sessionId) {
                  ref.notifier(serverProvider).acceptWebSendRequest(sessionId);
                },
                onDecline: (sessionId) {
                  ref.notifier(serverProvider).declineWebSendRequest(sessionId);
                },
                onClose: _requestClose,
              );
            },
          ),
        ),
      ),
    );
  }
}

@immutable
class _ShareAddress {
  const _ShareAddress({
    required this.displayUrl,
    required this.actionUrl,
  });

  final String displayUrl;
  final String actionUrl;
}

class _ServerStatusView extends StatelessWidget {
  const _ServerStatusView({
    required this.state,
    required this.error,
    required this.onRetry,
  });

  final _ServerState state;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    final theme = Theme.of(context);
    final isError = state == _ServerState.error;
    final title = switch (state) {
      _ServerState.initializing => copy.initializingTitle,
      _ServerState.running => copy.readyTitle,
      _ServerState.error => copy.errorTitle,
      _ServerState.stopping => copy.stoppingTitle,
    };
    final subtitle = switch (state) {
      _ServerState.initializing => copy.initializingSubtitle,
      _ServerState.running => copy.readySubtitle,
      _ServerState.error => copy.errorSubtitle,
      _ServerState.stopping => copy.stoppingSubtitle,
    };

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(LocalShareSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - LocalShareSpacing.xxl)
                    .clamp(0, double.infinity),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: LocalShareSurface(
                    style: isError
                        ? LocalShareSurfaceStyle.standard
                        : LocalShareSurfaceStyle.accent,
                    padding: const EdgeInsets.all(LocalShareSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: isError
                                ? theme.colorScheme.errorContainer
                                : theme.colorScheme.onPrimary.withOpacity(0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(LocalShareSpacing.md),
                            child: isError
                                ? Icon(
                                    Icons.error_outline_rounded,
                                    size: 34,
                                    color: theme.colorScheme.onErrorContainer,
                                  )
                                : SizedBox.square(
                                    dimension: 34,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: LocalShareSpacing.lg),
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: isError
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: LocalShareSpacing.xs),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isError
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onPrimary.withOpacity(0.78),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (isError && error != null) ...[
                          const SizedBox(height: LocalShareSpacing.lg),
                          LocalShareSurface(
                            style: LocalShareSurfaceStyle.subtle,
                            padding: const EdgeInsets.all(LocalShareSpacing.sm),
                            child: SelectableText(
                              error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        if (isError) ...[
                          const SizedBox(height: LocalShareSpacing.lg),
                          FilledButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(copy.retry),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RunningWebSendView extends StatelessWidget {
  const _RunningWebSendView({
    required this.addresses,
    required this.sessions,
    required this.fileCount,
    required this.encrypted,
    required this.autoAccept,
    required this.pin,
    required this.onEncryptionChanged,
    required this.onAutoAcceptChanged,
    required this.onPinChanged,
    required this.onAccept,
    required this.onDecline,
    required this.onClose,
  });

  final List<_ShareAddress> addresses;
  final List<WebSendSession> sessions;
  final int fileCount;
  final bool encrypted;
  final bool autoAccept;
  final String? pin;
  final ValueChanged<bool> onEncryptionChanged;
  final ValueChanged<bool> onAutoAcceptChanged;
  final ValueChanged<bool> onPinChanged;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onDecline;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        sessions.where((session) => session.responseHandler != null).length;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          LocalShareSpacing.md,
          LocalShareSpacing.sm,
          LocalShareSpacing.md,
          LocalShareSpacing.xxl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReadyHero(
                  fileCount: fileCount,
                  pendingCount: pendingCount,
                  encrypted: encrypted,
                ),
                const SizedBox(height: LocalShareSpacing.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final isWide =
                        constraints.maxWidth >= 800 && textScale <= 1.35;
                    final addressesSection = _AddressSection(
                      addresses: addresses,
                      pin: pin,
                      encrypted: encrypted,
                    );
                    final settingsSection = _SettingsSection(
                      encrypted: encrypted,
                      autoAccept: autoAccept,
                      pin: pin,
                      onEncryptionChanged: onEncryptionChanged,
                      onAutoAcceptChanged: onAutoAcceptChanged,
                      onPinChanged: onPinChanged,
                    );
                    final requestSection = _RequestSection(
                      sessions: sessions,
                      onAccept: onAccept,
                      onDecline: onDecline,
                    );

                    if (!isWide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          addressesSection,
                          const SizedBox(height: LocalShareSpacing.lg),
                          requestSection,
                          const SizedBox(height: LocalShareSpacing.lg),
                          settingsSection,
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: addressesSection),
                            const SizedBox(width: LocalShareSpacing.lg),
                            Expanded(flex: 5, child: settingsSection),
                          ],
                        ),
                        const SizedBox(height: LocalShareSpacing.lg),
                        requestSection,
                      ],
                    );
                  },
                ),
                const SizedBox(height: LocalShareSpacing.lg),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(_WebSendCopy.of(context).endSharing),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadyHero extends StatelessWidget {
  const _ReadyHero({
    required this.fileCount,
    required this.pendingCount,
    required this.encrypted,
  });

  final int fileCount;
  final int pendingCount;
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onPrimary;

    return LocalShareSurface(
      style: LocalShareSurfaceStyle.accent,
      padding: const EdgeInsets.all(LocalShareSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 540 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: LocalShareSpacing.xs,
                runSpacing: LocalShareSpacing.xs,
                children: [
                  _HeroBadge(
                    icon: Icons.circle,
                    label: copy.waitingForBrowser,
                    foreground: foreground,
                  ),
                  _HeroBadge(
                    icon: encrypted
                        ? Icons.lock_outline_rounded
                        : Icons.lan_outlined,
                    label: encrypted ? 'HTTPS' : 'HTTP',
                    foreground: foreground,
                  ),
                ],
              ),
              const SizedBox(height: LocalShareSpacing.lg),
              Text(
                copy.readyTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: LocalShareSpacing.xs),
              Text(
                copy.readySubtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: foreground.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: LocalShareSpacing.md),
              Wrap(
                spacing: LocalShareSpacing.sm,
                runSpacing: LocalShareSpacing.xs,
                children: [
                  Text(
                    copy.fileCount(fileCount),
                    style:
                        theme.textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                  Text(
                    copy.pendingCount(pendingCount),
                    style:
                        theme.textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return text;
          }
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: LocalShareSpacing.lg),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: foreground.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(LocalShareSpacing.lg),
                  child: Icon(
                    Icons.language_rounded,
                    color: foreground,
                    size: 40,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({
    required this.icon,
    required this.label,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: foreground.withOpacity(0.14),
        borderRadius: BorderRadius.circular(LocalShareRadii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LocalShareSpacing.sm,
          vertical: LocalShareSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: LocalShareSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressSection extends StatelessWidget {
  const _AddressSection({
    required this.addresses,
    required this.pin,
    required this.encrypted,
  });

  final List<_ShareAddress> addresses;
  final String? pin;
  final bool encrypted;

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    final theme = Theme.of(context);
    return LocalShareSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalShareSectionHeader(
            title: copy.addressesTitle,
            subtitle: copy.addressesSubtitle(addresses.length),
            leading: const Icon(Icons.link_rounded),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: LocalShareSpacing.md),
          if (addresses.isEmpty)
            LocalShareSurface(
              style: LocalShareSurfaceStyle.subtle,
              child: Column(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 36,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: LocalShareSpacing.sm),
                  Text(copy.noNetwork, style: theme.textTheme.titleSmall),
                  const SizedBox(height: LocalShareSpacing.xxs),
                  Text(
                    copy.noNetworkHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ...addresses.map(
              (address) => Padding(
                padding: const EdgeInsets.only(bottom: LocalShareSpacing.sm),
                child: _AddressCard(address: address, pin: pin),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                encrypted
                    ? Icons.lock_outline_rounded
                    : Icons.verified_user_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: LocalShareSpacing.xs),
              Expanded(
                child: Text(
                  encrypted ? copy.httpsSummary : copy.httpSummary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.pin});

  final _ShareAddress address;
  final String? pin;

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    final theme = Theme.of(context);
    return LocalShareSurface(
      style: LocalShareSurfaceStyle.tinted,
      padding: const EdgeInsets.all(LocalShareSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(LocalShareRadii.medium),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(LocalShareSpacing.xs),
                  child: Icon(
                    Icons.link_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: LocalShareSpacing.sm),
              Expanded(
                child: SelectableText(
                  address.displayUrl,
                  maxLines: 3,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LocalShareSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: LocalShareSpacing.xs,
            runSpacing: LocalShareSpacing.xs,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => QrDialog(
                      data: address.actionUrl,
                      label: address.displayUrl,
                      listenIncomingWebSendRequests: true,
                      pin: pin,
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_rounded),
                label: Text(copy.showQr),
              ),
              IconButton.filledTonal(
                tooltip: copy.copyLink,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: address.displayUrl),
                  );
                  if (context.mounted && checkPlatformIsDesktop()) {
                    context.showSnackBar(t.general.copiedToClipboard);
                  }
                },
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton.filledTonal(
                tooltip: copy.openBrowser,
                onPressed: () async {
                  final opened = await launchUrl(
                    Uri.parse(address.actionUrl),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!opened && context.mounted) {
                    context.showSnackBar(copy.browserError);
                  }
                },
                icon: const Icon(Icons.open_in_browser_rounded),
              ),
              IconButton.filledTonal(
                tooltip: copy.largeDisplay,
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => ZoomDialog(
                      label: address.displayUrl,
                      pin: pin,
                      listenIncomingWebSendRequests: true,
                    ),
                  );
                },
                icon: const Icon(Icons.tv_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({
    required this.sessions,
    required this.onAccept,
    required this.onDecline,
  });

  final List<WebSendSession> sessions;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onDecline;

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    final theme = Theme.of(context);
    final pending =
        sessions.where((session) => session.responseHandler != null).length;
    return LocalShareSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalShareSectionHeader(
            title: copy.requestsTitle,
            subtitle: copy.requestsSubtitle(sessions.length, pending),
            leading: const Icon(Icons.devices_other_rounded),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: LocalShareSpacing.md),
          if (sessions.isEmpty)
            LocalShareSurface(
              style: LocalShareSurfaceStyle.subtle,
              child: Column(
                children: [
                  Icon(
                    Icons.hourglass_empty_rounded,
                    size: 34,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: LocalShareSpacing.sm),
                  Text(copy.noRequests, style: theme.textTheme.titleSmall),
                  const SizedBox(height: LocalShareSpacing.xxs),
                  Text(
                    copy.noRequestsHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ...sessions.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: LocalShareSpacing.sm),
                child: _RequestCard(
                  session: session,
                  onAccept: () => onAccept(session.sessionId),
                  onDecline: () => onDecline(session.sessionId),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.session,
    required this.onAccept,
    required this.onDecline,
  });

  final WebSendSession session;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    final theme = Theme.of(context);
    final pending = session.responseHandler != null;
    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: pending
                ? context.localShareDesign.warning.withOpacity(0.14)
                : theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(LocalShareRadii.medium),
          ),
          child: Padding(
            padding: const EdgeInsets.all(LocalShareSpacing.sm),
            child: Icon(
              pending
                  ? Icons.notifications_active_outlined
                  : Icons.check_circle_outline_rounded,
              color: pending
                  ? context.localShareDesign.warning
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: LocalShareSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.deviceInfo, style: theme.textTheme.titleSmall),
              const SizedBox(height: LocalShareSpacing.xxs),
              Text(
                session.ip,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = pending
        ? Wrap(
            alignment: WrapAlignment.end,
            spacing: LocalShareSpacing.xs,
            runSpacing: LocalShareSpacing.xs,
            children: [
              OutlinedButton.icon(
                onPressed: onDecline,
                icon: const Icon(Icons.close_rounded),
                label: Text(copy.decline),
              ),
              FilledButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.check_rounded),
                label: Text(copy.accept),
              ),
            ],
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(LocalShareRadii.full),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LocalShareSpacing.sm,
                vertical: LocalShareSpacing.xs,
              ),
              child: Text(
                copy.accepted,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          );

    return LocalShareSurface(
      style: pending
          ? LocalShareSurfaceStyle.tinted
          : LocalShareSurfaceStyle.subtle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.25;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: LocalShareSpacing.sm),
                Align(
                    alignment: AlignmentDirectional.centerEnd, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: LocalShareSpacing.md),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.encrypted,
    required this.autoAccept,
    required this.pin,
    required this.onEncryptionChanged,
    required this.onAutoAcceptChanged,
    required this.onPinChanged,
  });

  final bool encrypted;
  final bool autoAccept;
  final String? pin;
  final ValueChanged<bool> onEncryptionChanged;
  final ValueChanged<bool> onAutoAcceptChanged;
  final ValueChanged<bool> onPinChanged;

  @override
  Widget build(BuildContext context) {
    final copy = _WebSendCopy.of(context);
    final theme = Theme.of(context);
    return LocalShareSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalShareSectionHeader(
            title: copy.settingsTitle,
            subtitle: copy.settingsSubtitle,
            leading: const Icon(Icons.tune_rounded),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: LocalShareSpacing.sm),
          _SettingToggle(
            icon: encrypted
                ? Icons.lock_outline_rounded
                : Icons.lock_open_rounded,
            title: copy.httpsTitle,
            subtitle: copy.httpsSubtitle,
            value: encrypted,
            onChanged: onEncryptionChanged,
          ),
          if (encrypted) ...[
            const SizedBox(height: LocalShareSpacing.xs),
            _SettingNotice(
              icon: Icons.info_outline_rounded,
              text: copy.selfSignedHint,
              color: context.localShareDesign.warning,
            ),
          ],
          const Divider(height: LocalShareSpacing.lg),
          _SettingToggle(
            icon: Icons.flash_on_outlined,
            title: copy.autoAcceptTitle,
            subtitle: copy.autoAcceptSubtitle,
            value: autoAccept,
            onChanged: onAutoAcceptChanged,
          ),
          const Divider(height: LocalShareSpacing.lg),
          _SettingToggle(
            icon: Icons.pin_outlined,
            title: copy.pinTitle,
            subtitle: copy.pinSubtitle,
            value: pin != null,
            onChanged: onPinChanged,
          ),
          if (pin != null) ...[
            const SizedBox(height: LocalShareSpacing.xs),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(LocalShareRadii.medium),
              ),
              child: Padding(
                padding: const EdgeInsets.all(LocalShareSpacing.sm),
                child: Row(
                  children: [
                    Icon(
                      Icons.key_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: LocalShareSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            copy.accessCode,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          SelectableText(
                            pin!,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: LocalShareSpacing.xs),
          child: Icon(icon, size: 22, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: LocalShareSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LocalShareSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: LocalShareSpacing.xxs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: LocalShareSpacing.xs),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SettingNotice extends StatelessWidget {
  const _SettingNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(LocalShareRadii.medium),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LocalShareSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: LocalShareSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _WebSendCopy {
  const _WebSendCopy(this.isChinese);

  factory _WebSendCopy.of(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return _WebSendCopy(languageCode.toLowerCase().startsWith('zh'));
  }

  final bool isChinese;

  String get pageTitle => isChinese ? '网页发送' : 'Web sharing';
  String get waitingForBrowser =>
      isChinese ? '等待浏览器连接' : 'Waiting for a browser';
  String get readyTitle => isChinese ? '分享链接已就绪' : 'Share link is ready';
  String get readySubtitle => isChinese
      ? '接收端连接同一局域网后打开下方地址，无需安装 LocalShare。'
      : 'On the same local network, open an address below. The receiver does not need LocalShare installed.';
  String get initializingTitle =>
      isChinese ? '正在准备分享链接' : 'Preparing your share link';
  String get initializingSubtitle => isChinese
      ? '正在启动本机网页服务，请稍候。'
      : 'Starting the local web service. This should only take a moment.';
  String get stoppingTitle => isChinese ? '正在结束网页发送' : 'Stopping web sharing';
  String get stoppingSubtitle => isChinese
      ? '正在关闭网页会话并恢复常规文件传输服务。'
      : 'Closing the web session and restoring regular file transfers.';
  String get errorTitle =>
      isChinese ? '网页发送启动失败' : 'Web sharing could not start';
  String get errorSubtitle => isChinese
      ? '请检查端口和网络权限，然后重试。'
      : 'Check the port and local-network permissions, then try again.';
  String get missingServerState => isChinese
      ? '网页服务状态丢失，请重新启动。'
      : 'The web service state is unavailable. Please restart it.';
  String get retry => isChinese ? '重试' : 'Try again';
  String fileCount(int count) => isChinese
      ? '已共享 $count 项内容'
      : '$count item${count == 1 ? '' : 's'} shared';
  String pendingCount(int count) => isChinese
      ? '$count 个待处理请求'
      : '$count pending request${count == 1 ? '' : 's'}';
  String get addressesTitle => isChinese ? '访问地址' : 'Open an address';
  String addressesSubtitle(int count) => isChinese
      ? count == 0
          ? '正在等待可用的局域网地址'
          : '任选一个地址，或向接收端展示二维码'
      : count == 0
          ? 'Waiting for an available local address'
          : 'Use any address or show its QR code to the receiver';
  String get noNetwork => isChinese ? '暂无可用地址' : 'No address available';
  String get noNetworkHint => isChinese
      ? '请确认设备已连接 Wi-Fi 或有线局域网。'
      : 'Connect this device to Wi-Fi or a wired local network.';
  String get httpSummary => isChinese
      ? '地址仅在当前局域网内可用；需要加密时可在设置中启用 HTTPS。'
      : 'These addresses only work on this local network. Enable HTTPS below when encryption is needed.';
  String get httpsSummary => isChinese
      ? '当前连接已启用 HTTPS，浏览器可能提示自签名证书。'
      : 'HTTPS is enabled. The browser may warn about the self-signed certificate.';
  String get showQr => isChinese ? '二维码' : 'QR code';
  String get copyLink => isChinese ? '复制地址' : 'Copy address';
  String get openBrowser => isChinese ? '在浏览器打开' : 'Open in browser';
  String get largeDisplay => isChinese ? '大屏展示' : 'Large display';
  String get browserError =>
      isChinese ? '无法打开浏览器' : 'The browser could not be opened';
  String get requestsTitle => isChinese ? '连接请求' : 'Connection requests';
  String requestsSubtitle(int total, int pending) => isChinese
      ? total == 0
          ? '浏览器连接后会显示在这里'
          : '共 $total 个连接，其中 $pending 个等待确认'
      : total == 0
          ? 'Browser connections will appear here'
          : '$total connection${total == 1 ? '' : 's'}, $pending waiting for approval';
  String get noRequests => isChinese ? '还没有连接请求' : 'No requests yet';
  String get noRequestsHint => isChinese
      ? '让接收端打开上方地址，连接请求会实时出现。'
      : 'Ask the receiver to open an address above. Requests appear here in real time.';
  String get accept => isChinese ? '允许' : 'Allow';
  String get decline => isChinese ? '拒绝' : 'Decline';
  String get accepted => isChinese ? '已允许' : 'Allowed';
  String get settingsTitle => isChinese ? '分享设置' : 'Sharing settings';
  String get settingsSubtitle =>
      isChinese ? '更改安全方式和请求审批规则' : 'Control security and request approvals';
  String get httpsTitle => isChinese ? '启用 HTTPS' : 'Enable HTTPS';
  String get httpsSubtitle => isChinese
      ? '加密浏览器与这台设备之间的传输'
      : 'Encrypt traffic between the browser and this device';
  String get selfSignedHint => isChinese
      ? 'HTTPS 使用 LocalShare 在本机生成的自签名证书。浏览器出现安全提示属于正常现象，请只在可信局域网中继续。'
      : 'HTTPS uses a self-signed certificate generated locally by LocalShare. A browser warning is expected; continue only on a trusted local network.';
  String get autoAcceptTitle =>
      isChinese ? '自动允许请求' : 'Automatically allow requests';
  String get autoAcceptSubtitle => isChinese
      ? '跳过逐个确认，适合仅有可信设备的网络'
      : 'Skip individual approval on networks with trusted devices only';
  String get pinTitle => isChinese ? '要求访问码' : 'Require an access code';
  String get pinSubtitle => isChinese
      ? '接收端必须输入访问码才能查看内容'
      : 'Receivers must enter a code before viewing the shared items';
  String get accessCode => isChinese ? '当前访问码' : 'Current access code';
  String get endSharing => isChinese ? '结束网页发送' : 'End web sharing';
}
