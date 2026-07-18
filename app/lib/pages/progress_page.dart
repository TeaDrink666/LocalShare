import 'dart:async';
import 'dart:typed_data';

import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/file_type.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/file_speed_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/native/taskbar_helper.dart';
import 'package:localsend_app/util/ui/nav_bar_padding.dart';
import 'package:localsend_app/widget/custom_progress_bar.dart';
import 'package:localsend_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class ProgressPage extends StatefulWidget {
  final bool showAppBar;
  final bool closeSessionOnClose;
  final String sessionId;

  const ProgressPage({
    required this.showAppBar,
    required this.closeSessionOnClose,
    required this.sessionId,
  });

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> with Refena {
  int _totalBytes = double.maxFinite.toInt();
  int _lastRemainingTimeUpdate = 0; // millis since epoch
  String? _remainingTime;
  List<FileDto> _files =
      []; // also contains declined files (files without token)
  Set<String> _selectedFiles = {};
  SessionStatus? _lastStatus;

  // If [autoFinish] is enabled, we wait a few seconds before automatically closing the session.
  int _finishCounter = 3;
  Timer? _finishTimer;
  Timer? _wakelockPlusTimer;

  bool _advanced = false;

  @override
  void initState() {
    super.initState();

    // init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        unawaited(WakelockPlus.enable());
      } catch (_) {}

      // Periodically call WakelockPlus.enable() to keep the screen awake
      _wakelockPlusTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        try {
          unawaited(WakelockPlus.enable());
        } catch (_) {}
      });

      if (ref.read(settingsProvider).autoFinish) {
        _finishTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          final finished = ref
                  .read(serverProvider)
                  ?.session
                  ?.files
                  .values
                  .map((e) => e.status)
                  .isFinishedOrSkipped ??
              ref
                  .read(sendProvider)[widget.sessionId]
                  ?.files
                  .values
                  .map((e) => e.status)
                  .isFinishedOrSkipped ??
              true;
          if (finished) {
            if (_finishCounter == 1) {
              timer.cancel();
              _exit(closeSession: true);
            } else {
              setState(() {
                _finishCounter--;
              });
            }
          }
        });
      }

      setState(() {
        final receiveSession = ref.read(serverProvider)?.session;
        if (receiveSession != null) {
          _files = receiveSession.files.values.map((f) => f.file).toList();

          // We previously used f.token != null here, but this may not work on very fast networks.
          _selectedFiles = receiveSession.files.values
              .where((f) => f.status != FileStatus.skipped)
              .map((f) => f.file.id)
              .toSet();
        } else {
          final sendSession = ref.read(sendProvider)[widget.sessionId];
          if (sendSession != null) {
            _files = sendSession.files.values.map((f) => f.file).toList();
            _selectedFiles = sendSession.files.values
                .where((f) => f.status != FileStatus.skipped)
                .map((f) => f.file.id)
                .toSet();
          }
        }

        _totalBytes = _files
            .where((f) => _selectedFiles.contains(f.id))
            .fold(0, (prev, curr) => prev + curr.size);
      });
    });
  }

  void _exit({required bool closeSession}) async {
    final receiveSession = ref.read(serverProvider.select((s) => s?.session));
    final sendSession = ref.read(sendProvider)[widget.sessionId];
    final SessionStatus? status = receiveSession?.status ?? sendSession?.status;
    final keepSession = !closeSession &&
        (status == SessionStatus.sending ||
            status == SessionStatus.finishedWithErrors);
    final result =
        status == null || keepSession || await _askCancelConfirmation(status);

    if (result && mounted) {
      // ignore: unawaited_futures
      context.popUntilRoot();
    }
  }

  Future<bool> _askCancelConfirmation(SessionStatus status) async {
    final bool result = switch (status == SessionStatus.sending) {
      true =>
        (await context.pushBottomSheet(() => const CancelSessionDialog())) ==
            true,
      false => true,
    };
    if (result) {
      final receiveSession = ref.read(serverProvider)?.session;
      final sendState = ref.read(sendProvider)[widget.sessionId];

      if (receiveSession != null) {
        if (receiveSession.status == SessionStatus.sending) {
          ref.notifier(serverProvider).cancelSession();
        } else {
          ref.notifier(serverProvider).closeSession();
        }
      } else if (sendState != null) {
        if (sendState.status == SessionStatus.sending) {
          ref.notifier(sendProvider).cancelSession(widget.sessionId);
        } else {
          ref.notifier(sendProvider).closeSession(widget.sessionId);
        }
      }
    }
    return result;
  }

  @override
  void dispose() {
    super.dispose();
    _finishTimer?.cancel();
    _wakelockPlusTimer?.cancel();
    TaskbarHelper.clearProgressBar(); // ignore: discarded_futures
    try {
      WakelockPlus.disable(); // ignore: discarded_futures
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final progressNotifier = ref.watch(progressProvider);
    final currBytes = _files.fold<int>(
        0,
        (prev, curr) =>
            prev +
            ((progressNotifier.getProgress(
                        sessionId: widget.sessionId, fileId: curr.id) *
                    curr.size)
                .round()));

    final receiveSession = ref.watch(serverProvider.select((s) => s?.session));
    final sendSession = ref.watch(sendProvider)[widget.sessionId];

    final SessionStatus? status = receiveSession?.status ?? sendSession?.status;

    if (status == SessionStatus.sending) {
      // ignore: discarded_futures
      TaskbarHelper.setProgressBar(currBytes, _totalBytes);
    } else if (status != _lastStatus) {
      _lastStatus = status;
      // ignore: discarded_futures
      TaskbarHelper.visualizeStatus(status);
    }

    if (status == null) {
      return Scaffold(
        body: Container(),
      );
    }

    final title = receiveSession != null
        ? t.progressPage.titleReceiving
        : t.progressPage.titleSending;
    final startTime = receiveSession?.startTime ?? sendSession?.startTime;
    final endTime = receiveSession?.endTime ?? sendSession?.endTime;
    final int? speedInBytes;
    if (startTime != null && currBytes >= 500 * 1024) {
      speedInBytes = getFileSpeed(
          start: startTime,
          end: endTime ?? DateTime.now().millisecondsSinceEpoch,
          bytes: currBytes);

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastRemainingTimeUpdate >= 1000) {
        _remainingTime = getRemainingTime(
            bytesPerSeconds: speedInBytes,
            remainingBytes: _totalBytes - currBytes);
        _lastRemainingTimeUpdate = now;
      }
    } else {
      speedInBytes = null;
    }

    final fileStatusMap =
        receiveSession?.files.map((k, f) => MapEntry(k, f.status)) ??
            sendSession!.files.map((k, f) => MapEntry(k, f.status));
    final finishedCount =
        fileStatusMap.values.where((s) => s == FileStatus.finished).length;

    final knownTotalBytes =
        _totalBytes == double.maxFinite.toInt() ? null : _totalBytes;
    final totalProgress = knownTotalBytes == null || knownTotalBytes == 0
        ? 0.0
        : (currBytes / knownTotalBytes).clamp(0.0, 1.0);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Already popped.
          // Because the user cannot pop this page, we can safely assume that all sessions are closed if they should be.
          return;
        }
        _exit(closeSession: widget.closeSessionOnClose);
      },
      canPop: false,
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: Text(title),
                surfaceTintColor: Colors.transparent,
              )
            : null,
        body: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.showAppBar ? 16 : MediaQuery.paddingOf(context).top + 20,
            16,
            24 + getNavBarPadding(context),
          ),
          itemCount: _files.length + 5,
          itemBuilder: (context, index) {
            late final Widget item;

            if (index == 0) {
              item = _ProgressPageIntro(
                title: title,
                showTitle: !widget.showAppBar,
                receiving: receiveSession != null,
                destinationDirectory:
                    checkPlatformWithFileSystem() && receiveSession != null
                        ? receiveSession.destinationDirectory
                        : null,
                canOpenDestination: !checkPlatform([TargetPlatform.iOS]),
                onOpenDestination: receiveSession == null
                    ? null
                    : () async {
                        await openFolder(
                            folderPath: receiveSession.destinationDirectory);
                      },
              );
            } else if (index == 1) {
              item = _ProgressHeroCard(
                status: status,
                progress: totalProgress,
                currentBytes: currBytes,
                totalBytes: knownTotalBytes,
                speedInBytes: speedInBytes,
                remainingTime: _remainingTime,
                finishedCount: finishedCount,
                selectedCount: _selectedFiles.length,
                advanced: _advanced,
                finishCounter: _finishTimer == null ? null : _finishCounter,
                onToggleAdvanced: () {
                  setState(() => _advanced = !_advanced);
                },
                onExit: () => _exit(closeSession: true),
              );
            } else if (index == 2) {
              final errorMessage = sendSession?.errorMessage;
              item = errorMessage == null
                  ? const SizedBox.shrink()
                  : _SessionErrorCard(errorMessage: errorMessage);
            } else if (index == 3) {
              item = _FileSectionHeader(
                fileCount: _files.length,
                finishedCount: finishedCount,
              );
            } else if (index == _files.length + 4) {
              item = const SizedBox(height: 12);
            } else {
              final file = _files[index - 4];
              final String fileName =
                  receiveSession?.files[file.id]?.desiredName ?? file.fileName;
              final fileStatus = fileStatusMap[file.id]!;
              final savedToGallery =
                  receiveSession?.files[file.id]?.savedToGallery ?? false;

              final String? filePath;
              if (receiveSession != null &&
                  fileStatus == FileStatus.finished &&
                  !savedToGallery) {
                filePath = receiveSession.files[file.id]!.path;
              } else if (sendSession != null) {
                filePath = sendSession.files[file.id]!.path;
              } else {
                filePath = null;
              }

              final String? errorMessage;
              if (receiveSession != null) {
                errorMessage = receiveSession.files[file.id]!.errorMessage;
              } else if (sendSession != null) {
                errorMessage = sendSession.files[file.id]!.errorMessage;
              } else {
                errorMessage = null;
              }

              final Uint8List? thumbnail;
              final AssetEntity? asset;
              if (sendSession != null) {
                thumbnail = sendSession.files[file.id]!.thumbnail;
                asset = sendSession.files[file.id]!.asset;
              } else {
                thumbnail = null;
                asset = null;
              }

              item = _ProgressFileCard(
                fileName: fileName,
                fileSize: file.size.asReadableFileSize,
                fileStatus: fileStatus,
                savedToGallery: savedToGallery,
                progress: progressNotifier.getProgress(
                    sessionId: widget.sessionId, fileId: file.id),
                thumbnail: thumbnail,
                asset: asset,
                filePath: filePath,
                fileType: file.fileType,
                errorMessage: errorMessage,
                onOpen: filePath != null && receiveSession != null
                    ? () async => openFile(context, file.fileType, filePath!)
                    : null,
                onShowError: errorMessage == null
                    ? null
                    : () async {
                        await showDialog(
                          context: context,
                          builder: (_) => ErrorDialog(error: errorMessage!),
                        );
                      },
                onRetry: sendSession != null && fileStatus == FileStatus.failed
                    ? () async {
                        await ref.notifier(sendProvider).sendFile(
                              sessionId: widget.sessionId,
                              isolateIndex: 0,
                              file: sendSession.files[file.id]!,
                              isRetry: true,
                            );
                      }
                    : null,
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: index == _files.length + 4 ? 0 : 12),
                  child: item,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProgressPageIntro extends StatelessWidget {
  final String title;
  final bool showTitle;
  final bool receiving;
  final String? destinationDirectory;
  final bool canOpenDestination;
  final Future<void> Function()? onOpenDestination;

  const _ProgressPageIntro({
    required this.title,
    required this.showTitle,
    required this.receiving,
    required this.destinationDirectory,
    required this.canOpenDestination,
    required this.onOpenDestination,
  });

  @override
  Widget build(BuildContext context) {
    if (!showTitle && destinationDirectory == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            receiving
                ? _ProgressCopy.receivingSubtitle
                : _ProgressCopy.sendingSubtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
        if (showTitle && destinationDirectory != null)
          const SizedBox(height: 16),
        if (destinationDirectory != null)
          Material(
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant.withOpacity(0.62)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: canOpenDestination ? onOpenDestination : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(Icons.folder_rounded,
                          color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.settingsTab.receive.destination,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destinationDirectory!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (canOpenDestination) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _ProgressCopy.openFolder,
                        child: Icon(Icons.open_in_new_rounded,
                            size: 20, color: scheme.primary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProgressHeroCard extends StatelessWidget {
  final SessionStatus status;
  final double progress;
  final int currentBytes;
  final int? totalBytes;
  final int? speedInBytes;
  final String? remainingTime;
  final int finishedCount;
  final int selectedCount;
  final bool advanced;
  final int? finishCounter;
  final VoidCallback onToggleAdvanced;
  final VoidCallback onExit;

  const _ProgressHeroCard({
    required this.status,
    required this.progress,
    required this.currentBytes,
    required this.totalBytes,
    required this.speedInBytes,
    required this.remainingTime,
    required this.finishedCount,
    required this.selectedCount,
    required this.advanced,
    required this.finishCounter,
    required this.onToggleAdvanced,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _sessionStatusColor(context, status);
    final percentage = (progress * 100).round();
    final statusLabel = status.getLabel(remainingTime: remainingTime ?? '-');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(
                accent.withOpacity(0.13), scheme.surfaceContainerLow),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.09),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(17),
                ),
                child:
                    Icon(_sessionStatusIcon(status), color: accent, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ProgressCopy.overallProgress,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusLabel.isEmpty
                          ? _ProgressCopy.processing
                          : statusLabel,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$percentage%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, value, child) {
              return CustomProgressBar(
                progress: value,
                borderRadius: 7,
              );
            },
          ),
          const SizedBox(height: 18),
          _ProgressMetrics(
            currentBytes: currentBytes,
            totalBytes: totalBytes,
            speedInBytes: speedInBytes,
            remainingTime: remainingTime,
            finishedCount: finishedCount,
            selectedCount: selectedCount,
          ),
          AnimatedCrossFade(
            crossFadeState:
                advanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topLeft,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.progressPage.total
                          .count(curr: finishedCount, n: selectedCount),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      t.progressPage.total.size(
                        curr: currentBytes.asReadableFileSize,
                        n: totalBytes?.asReadableFileSize ?? '-',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (speedInBytes != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        t.progressPage.total
                            .speed(speed: speedInBytes!.asReadableFileSize),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ProgressActions(
            advanced: advanced,
            sending: status == SessionStatus.sending,
            finishCounter: finishCounter,
            onToggleAdvanced: onToggleAdvanced,
            onExit: onExit,
          ),
        ],
      ),
    );
  }
}

class _ProgressMetrics extends StatelessWidget {
  final int currentBytes;
  final int? totalBytes;
  final int? speedInBytes;
  final String? remainingTime;
  final int finishedCount;
  final int selectedCount;

  const _ProgressMetrics({
    required this.currentBytes,
    required this.totalBytes,
    required this.speedInBytes,
    required this.remainingTime,
    required this.finishedCount,
    required this.selectedCount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 440
                ? 2
                : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _ProgressMetric(
              width: width,
              icon: Icons.insert_drive_file_outlined,
              label: _ProgressCopy.files,
              value: '$finishedCount / $selectedCount',
            ),
            _ProgressMetric(
              width: width,
              icon: Icons.data_usage_rounded,
              label: _ProgressCopy.transferred,
              value:
                  '${currentBytes.asReadableFileSize} / ${totalBytes?.asReadableFileSize ?? '-'}',
            ),
            _ProgressMetric(
              width: width,
              icon: Icons.speed_rounded,
              label: _ProgressCopy.speed,
              value: speedInBytes == null
                  ? '-'
                  : '${speedInBytes!.asReadableFileSize}/s',
            ),
            _ProgressMetric(
              width: width,
              icon: Icons.schedule_rounded,
              label: _ProgressCopy.remaining,
              value: remainingTime ?? '-',
            ),
          ],
        );
      },
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;

  const _ProgressMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.62),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressActions extends StatelessWidget {
  final bool advanced;
  final bool sending;
  final int? finishCounter;
  final VoidCallback onToggleAdvanced;
  final VoidCallback onExit;

  const _ProgressActions({
    required this.advanced,
    required this.sending,
    required this.finishCounter,
    required this.onToggleAdvanced,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final advancedButton = OutlinedButton.icon(
      onPressed: onToggleAdvanced,
      icon: Icon(advanced ? Icons.expand_less_rounded : Icons.tune_rounded),
      label: Text(advanced ? t.general.hide : t.general.advanced),
    );
    final exitButton = FilledButton.icon(
      style: sending
          ? FilledButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            )
          : null,
      onPressed: onExit,
      icon: Icon(sending ? Icons.close_rounded : Icons.check_circle_rounded),
      label: Text(
        sending
            ? t.general.cancel
            : finishCounter != null
                ? '${t.general.done} ($finishCounter)'
                : t.general.done,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: double.infinity, child: advancedButton),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: exitButton),
            ],
          );
        }

        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 8,
          children: [advancedButton, exitButton],
        );
      },
    );
  }
}

class _SessionErrorCard extends StatelessWidget {
  final String errorMessage;

  const _SessionErrorCard({required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withOpacity(0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.error.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              errorMessage,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onErrorContainer, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileSectionHeader extends StatelessWidget {
  final int fileCount;
  final int finishedCount;

  const _FileSectionHeader(
      {required this.fileCount, required this.finishedCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              _ProgressCopy.fileDetails,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$finishedCount / $fileCount',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressFileCard extends StatelessWidget {
  final String fileName;
  final String fileSize;
  final FileStatus fileStatus;
  final bool savedToGallery;
  final double progress;
  final Uint8List? thumbnail;
  final AssetEntity? asset;
  final String? filePath;
  final FileType fileType;
  final String? errorMessage;
  final Future<void> Function()? onOpen;
  final Future<void> Function()? onShowError;
  final Future<void> Function()? onRetry;

  const _ProgressFileCard({
    required this.fileName,
    required this.fileSize,
    required this.fileStatus,
    required this.savedToGallery,
    required this.progress,
    required this.thumbnail,
    required this.asset,
    required this.filePath,
    required this.fileType,
    required this.errorMessage,
    required this.onOpen,
    required this.onShowError,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = fileStatus.getColor(context);

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: statusColor
                .withOpacity(fileStatus == FileStatus.sending ? 0.42 : 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SmartFileThumbnail(
                bytes: thumbnail,
                asset: asset,
                path: filePath,
                fileType: fileType,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fileSize,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 9),
                    if (fileStatus == FileStatus.sending)
                      Row(
                        children: [
                          Expanded(
                            child: CustomProgressBar(
                              progress: progress.clamp(0.0, 1.0),
                              borderRadius: 5,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Icon(_fileStatusIcon(fileStatus),
                              size: 18, color: statusColor),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              savedToGallery
                                  ? t.progressPage.savedToGallery
                                  : fileStatus.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (errorMessage != null && onShowError != null) ...[
                            const SizedBox(width: 5),
                            Tooltip(
                              message: _ProgressCopy.showError,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: onShowError,
                                icon: Icon(Icons.info_outline_rounded,
                                    color: scheme.warning, size: 20),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: _ProgressCopy.retry,
                  child: IconButton.filledTonal(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color _sessionStatusColor(BuildContext context, SessionStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    SessionStatus.sending => scheme.primary,
    SessionStatus.finished => scheme.tertiary,
    SessionStatus.finishedWithErrors => scheme.error,
    SessionStatus.canceledBySender ||
    SessionStatus.canceledByReceiver =>
      scheme.onSurfaceVariant,
    _ => scheme.secondary,
  };
}

IconData _sessionStatusIcon(SessionStatus status) {
  return switch (status) {
    SessionStatus.sending => Icons.swap_vert_circle_outlined,
    SessionStatus.finished => Icons.check_circle_outline_rounded,
    SessionStatus.finishedWithErrors => Icons.error_outline_rounded,
    SessionStatus.canceledBySender ||
    SessionStatus.canceledByReceiver =>
      Icons.cancel_outlined,
    _ => Icons.hourglass_top_rounded,
  };
}

IconData _fileStatusIcon(FileStatus status) {
  return switch (status) {
    FileStatus.queue => Icons.schedule_rounded,
    FileStatus.skipped => Icons.skip_next_rounded,
    FileStatus.sending => Icons.sync_rounded,
    FileStatus.failed => Icons.error_outline_rounded,
    FileStatus.finished => Icons.check_circle_outline_rounded,
  };
}

abstract final class _ProgressCopy {
  static bool get _isChinese => switch (LocaleSettings.currentLocale) {
        AppLocale.zhCn || AppLocale.zhHk || AppLocale.zhTw => true,
        _ => false,
      };

  static String get receivingSubtitle => _isChinese
      ? '文件正在通过局域网传入当前设备。'
      : 'Files are arriving on this device over your local network.';
  static String get sendingSubtitle => _isChinese
      ? '文件正在通过局域网发送到对方设备。'
      : 'Files are being sent to the other device over your local network.';
  static String get openFolder =>
      _isChinese ? '打开保存位置' : 'Open destination folder';
  static String get overallProgress => _isChinese ? '总进度' : 'Overall progress';
  static String get processing => _isChinese ? '正在处理' : 'Processing';
  static String get files => _isChinese ? '文件' : 'Files';
  static String get transferred => _isChinese ? '已传输' : 'Transferred';
  static String get speed => _isChinese ? '速度' : 'Speed';
  static String get remaining => _isChinese ? '剩余时间' : 'Remaining';
  static String get fileDetails => _isChinese ? '文件详情' : 'File details';
  static String get showError => _isChinese ? '查看错误' : 'Show error';
  static String get retry => _isChinese ? '重试' : 'Retry';
}

extension on FileStatus {
  String get label {
    switch (this) {
      case FileStatus.queue:
        return t.general.queue;
      case FileStatus.skipped:
        return t.general.skipped;
      case FileStatus.sending:
        return ''; // progress bar will be showed here
      case FileStatus.failed:
        return t.general.error;
      case FileStatus.finished:
        return t.general.done;
    }
  }

  Color getColor(BuildContext context) {
    switch (this) {
      case FileStatus.queue:
        return Theme.of(context).colorScheme.primary;
      case FileStatus.skipped:
        return Colors.grey;
      case FileStatus.sending:
        return Theme.of(context).colorScheme.primary;
      case FileStatus.failed:
        return Theme.of(context).colorScheme.warning;
      case FileStatus.finished:
        return Theme.of(context).colorScheme.primary;
    }
  }
}

extension on SessionStatus {
  String getLabel({required String remainingTime}) {
    switch (this) {
      case SessionStatus.sending:
        return t.progressPage.total.title.sending(
          time: remainingTime,
        );
      case SessionStatus.finished:
        return t.general.finished;
      case SessionStatus.finishedWithErrors:
        return t.progressPage.total.title.finishedError;
      case SessionStatus.canceledBySender:
        return t.progressPage.total.title.canceledSender;
      case SessionStatus.canceledByReceiver:
        return t.progressPage.total.title.canceledReceiver;
      default:
        return '';
    }
  }
}
