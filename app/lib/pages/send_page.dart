import 'dart:async';

import 'package:common/model/device.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/native/taskbar_helper.dart';
import 'package:localsend_app/widget/animations/initial_fade_transition.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_app/widget/localshare_design/localshare_page_background.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class SendPage extends StatefulWidget {
  final bool showAppBar;
  final bool closeSessionOnClose;
  final String sessionId;

  const SendPage({
    required this.showAppBar,
    required this.closeSessionOnClose,
    required this.sessionId,
  });

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with Refena {
  Device? _myDevice;
  Device? _targetDevice;

  @override
  void dispose() {
    super.dispose();
    unawaited(TaskbarHelper.clearProgressBar());
  }

  void _cancel() {
    // the state will be lost so we store them temporarily (only for UI)
    final myDevice = ref.read(deviceFullInfoProvider);
    final sendState = ref.read(sendProvider)[widget.sessionId];
    if (sendState == null) {
      return;
    }

    setState(() {
      _myDevice = myDevice;
      _targetDevice = sendState.target;
    });
    ref.notifier(sendProvider).cancelSession(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final sendState = ref
        .watch(sendProvider.select((state) => state[widget.sessionId]),
            listener: (prev, next) {
      final prevStatus = prev[widget.sessionId]?.status;
      final nextStatus = next[widget.sessionId]?.status;
      if (prevStatus != nextStatus) {
        // ignore: discarded_futures
        TaskbarHelper.visualizeStatus(nextStatus);
      }
    });
    if (sendState == null && _myDevice == null && _targetDevice == null) {
      return Scaffold(
        body: Container(),
      );
    }
    final myDevice = ref.watch(deviceFullInfoProvider);
    final targetDevice = sendState?.target ?? _targetDevice!;
    final targetFavoriteEntry = ref.watch(
      favoritesProvider.select((state) => state.findDevice(targetDevice)),
    );
    final waiting = sendState?.status == SessionStatus.waiting;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && widget.closeSessionOnClose) {
          _cancel();
        }
      },
      canPop: true,
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(title: Text(_SendPageCopy.pageTitle))
            : null,
        body: LocalSharePageBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final horizontalPadding = viewport.maxWidth < 520 ? 16.0 : 28.0;
                final verticalPadding = viewport.maxHeight < 620 ? 16.0 : 28.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 920,
                        minHeight: (viewport.maxHeight - verticalPadding * 2)
                            .clamp(0.0, double.infinity),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _PageHeading(),
                          const SizedBox(height: 22),
                          _DeviceRelationshipCard(
                            myDevice: myDevice,
                            targetDevice: targetDevice,
                            targetName: targetFavoriteEntry?.alias ??
                                targetDevice.alias,
                          ),
                          if (sendState != null) ...[
                            const SizedBox(height: 18),
                            InitialFadeTransition(
                              duration: const Duration(milliseconds: 300),
                              delay: const Duration(milliseconds: 250),
                              child: _StatusCard(
                                status: sendState.status,
                                targetName: targetFavoriteEntry?.alias ??
                                    targetDevice.alias,
                                errorMessage: sendState.errorMessage,
                                onShowError: sendState.errorMessage == null
                                    ? null
                                    : () async {
                                        await showDialog(
                                          context: context,
                                          builder: (_) => ErrorDialog(
                                            error: sendState.errorMessage!,
                                          ),
                                        );
                                      },
                              ),
                            ),
                            const SizedBox(height: 18),
                            _PageAction(
                              waiting: waiting,
                              onPressed: () {
                                _cancel();
                                context.pop();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.send_rounded,
                color: scheme.onPrimaryContainer,
                size: 23,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                _SendPageCopy.pageTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _SendPageCopy.pageSubtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _DeviceRelationshipCard extends StatelessWidget {
  final Device myDevice;
  final Device targetDevice;
  final String targetName;

  const _DeviceRelationshipCard({
    required this.myDevice,
    required this.targetDevice,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.58)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(
              theme.brightness == Brightness.dark ? 0.16 : 0.06,
            ),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(16);
          final horizontal = constraints.maxWidth >= 680 && textScale <= 20;
          final source = _DeviceCard(
            device: myDevice,
            name: myDevice.alias,
            role: _SendPageCopy.thisDevice,
            accent: scheme.primary,
          );
          final target = Hero(
            tag: 'device-${targetDevice.ip}',
            child: Material(
              color: Colors.transparent,
              child: _DeviceCard(
                device: targetDevice,
                name: targetName,
                role: _SendPageCopy.receivingDevice,
                accent: scheme.tertiary,
              ),
            ),
          );
          final direction = Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              horizontal
                  ? Icons.arrow_forward_rounded
                  : Icons.arrow_downward_rounded,
              color: scheme.onPrimaryContainer,
            ),
          );

          if (!horizontal) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                source,
                const SizedBox(height: 12),
                Align(alignment: Alignment.center, child: direction),
                const SizedBox(height: 12),
                target,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: source),
              const SizedBox(width: 14),
              direction,
              const SizedBox(width: 14),
              Expanded(child: target),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final String name;
  final String role;
  final Color accent;

  const _DeviceCard({
    required this.device,
    required this.name,
    required this.role,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final model = device.deviceModel?.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(
          theme.brightness == Brightness.dark ? 0.32 : 0.42,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(device.deviceType.icon, color: accent, size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  model == null || model.isEmpty
                      ? device.ip
                      : '$model · ${device.ip}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
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

class _StatusCard extends StatelessWidget {
  final SessionStatus status;
  final String targetName;
  final String? errorMessage;
  final VoidCallback? onShowError;

  const _StatusCard({
    required this.status,
    required this.targetName,
    required this.errorMessage,
    required this.onShowError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presentation = _StatusPresentation.from(
      status: status,
      targetName: targetName,
      scheme: scheme,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: presentation.accent.withOpacity(
          theme.brightness == Brightness.dark ? 0.12 : 0.08,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: presentation.accent.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: presentation.accent.withOpacity(0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: status == SessionStatus.waiting
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: presentation.accent,
                    ),
                  )
                : Icon(
                    presentation.icon,
                    color: presentation.accent,
                    size: 25,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  presentation.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (errorMessage != null && onShowError != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onShowError,
                    icon: const Icon(Icons.info_outline_rounded, size: 19),
                    label: Text(_SendPageCopy.viewDetails),
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

class _PageAction extends StatelessWidget {
  final bool waiting;
  final VoidCallback onPressed;

  const _PageAction({required this.waiting, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(220, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      onPressed: onPressed,
      icon: Icon(
        waiting ? Icons.close_rounded : Icons.check_circle_outline_rounded,
      ),
      label: Text(waiting ? _SendPageCopy.cancel : _SendPageCopy.close),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 440 ||
            MediaQuery.textScalerOf(context).scale(16) > 20) {
          return SizedBox(width: double.infinity, child: button);
        }
        return Align(alignment: Alignment.centerRight, child: button);
      },
    );
  }
}

class _StatusPresentation {
  final IconData icon;
  final Color accent;
  final String title;
  final String description;

  const _StatusPresentation({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
  });

  factory _StatusPresentation.from({
    required SessionStatus status,
    required String targetName,
    required ColorScheme scheme,
  }) {
    return switch (status) {
      SessionStatus.waiting => _StatusPresentation(
          icon: Icons.hourglass_top_rounded,
          accent: scheme.primary,
          title: _SendPageCopy.waitingTitle,
          description: _SendPageCopy.waitingDescription(targetName),
        ),
      SessionStatus.recipientBusy => _StatusPresentation(
          icon: Icons.schedule_rounded,
          accent: scheme.tertiary,
          title: _SendPageCopy.busyTitle,
          description: _SendPageCopy.busyDescription,
        ),
      SessionStatus.declined => _StatusPresentation(
          icon: Icons.block_rounded,
          accent: scheme.error,
          title: _SendPageCopy.declinedTitle,
          description: _SendPageCopy.declinedDescription(targetName),
        ),
      SessionStatus.tooManyAttempts => _StatusPresentation(
          icon: Icons.lock_clock_outlined,
          accent: scheme.error,
          title: _SendPageCopy.tooManyAttemptsTitle,
          description: _SendPageCopy.tooManyAttemptsDescription,
        ),
      SessionStatus.finishedWithErrors => _StatusPresentation(
          icon: Icons.error_outline_rounded,
          accent: scheme.error,
          title: _SendPageCopy.errorTitle,
          description: _SendPageCopy.errorDescription,
        ),
      SessionStatus.sending => _StatusPresentation(
          icon: Icons.sync_rounded,
          accent: scheme.primary,
          title: _SendPageCopy.startingTitle,
          description: _SendPageCopy.startingDescription,
        ),
      SessionStatus.finished => _StatusPresentation(
          icon: Icons.check_circle_outline_rounded,
          accent: scheme.primary,
          title: _SendPageCopy.finishedTitle,
          description: _SendPageCopy.finishedDescription,
        ),
      SessionStatus.canceledBySender => _StatusPresentation(
          icon: Icons.cancel_outlined,
          accent: scheme.onSurfaceVariant,
          title: _SendPageCopy.canceledTitle,
          description: _SendPageCopy.canceledDescription,
        ),
      SessionStatus.canceledByReceiver => _StatusPresentation(
          icon: Icons.cancel_outlined,
          accent: scheme.error,
          title: _SendPageCopy.receiverCanceledTitle,
          description: _SendPageCopy.receiverCanceledDescription,
        ),
    };
  }
}

abstract final class _SendPageCopy {
  static bool get _zh => LocalShareCopy.isChinese;

  static String get pageTitle => _zh ? '设备互传' : 'Device transfer';
  static String get pageSubtitle => _zh
      ? '正在通过局域网建立安全的点对点连接。'
      : 'Establishing a secure peer-to-peer connection over your LAN.';
  static String get thisDevice => _zh ? '当前设备' : 'This device';
  static String get receivingDevice => _zh ? '接收设备' : 'Receiving device';
  static String get waitingTitle => _zh ? '等待对方确认' : 'Waiting for approval';
  static String waitingDescription(String name) => _zh
      ? '已向 $name 发出传输请求，请在对方设备上确认。'
      : 'A transfer request was sent to $name. Approve it on the receiving device.';
  static String get busyTitle => _zh ? '对方设备正忙' : 'Receiving device is busy';
  static String get busyDescription => _zh
      ? '对方正在处理另一项传输，请稍后重试。'
      : 'The device is handling another transfer. Try again shortly.';
  static String get declinedTitle => _zh ? '对方已拒绝接收' : 'Request declined';
  static String declinedDescription(String name) =>
      _zh ? '$name 没有接受本次传输请求。' : '$name did not accept this transfer request.';
  static String get tooManyAttemptsTitle =>
      _zh ? '尝试次数过多' : 'Too many attempts';
  static String get tooManyAttemptsDescription => _zh
      ? '验证未通过，连接已停止。请确认 PIN 后重新发送。'
      : 'Verification failed and the connection was stopped. Check the PIN and try again.';
  static String get errorTitle =>
      _zh ? '传输出现问题' : 'Transfer encountered a problem';
  static String get errorDescription => _zh
      ? '部分内容未能完成传输，你可以查看错误详情。'
      : 'Some items could not be transferred. Review the error details.';
  static String get startingTitle => _zh ? '正在开始传输' : 'Starting transfer';
  static String get startingDescription => _zh
      ? '连接已确认，正在准备文件传输。'
      : 'The connection is approved and the files are being prepared.';
  static String get finishedTitle => _zh ? '传输已完成' : 'Transfer complete';
  static String get finishedDescription =>
      _zh ? '所有内容均已发送到对方设备。' : 'All items were sent to the receiving device.';
  static String get canceledTitle => _zh ? '传输已取消' : 'Transfer canceled';
  static String get canceledDescription =>
      _zh ? '你已停止本次传输。' : 'You stopped this transfer.';
  static String get receiverCanceledTitle =>
      _zh ? '对方已取消传输' : 'Canceled by receiver';
  static String get receiverCanceledDescription =>
      _zh ? '接收设备已停止本次传输。' : 'The receiving device stopped this transfer.';
  static String get viewDetails => _zh ? '查看错误详情' : 'View error details';
  static String get cancel => _zh ? '取消发送' : 'Cancel transfer';
  static String get close => _zh ? '关闭' : 'Close';
}
