import 'dart:io';
import 'package:common/constants.dart';
import 'package:common/model/device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/pages/about/about_page.dart';
import 'package:localsend_app/pages/changelog_page.dart';
import 'package:localsend_app/pages/donation/donation_page.dart';
import 'package:localsend_app/pages/language_page.dart';
import 'package:localsend_app/pages/settings/network_interfaces_page.dart';
import 'package:localsend_app/pages/tabs/settings_tab_controller.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/util/alias_generator.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/macos_channel.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/custom_dropdown_button.dart';
import 'package:localsend_app/widget/dialogs/encryption_disabled_notice.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_app/widget/dialogs/quick_save_from_favorites_notice.dart';
import 'package:localsend_app/widget/dialogs/quick_save_notice.dart';
import 'package:localsend_app/widget/dialogs/text_field_tv.dart';
import 'package:localsend_app/widget/dialogs/text_field_with_actions.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: settingsTabControllerProvider,
      builder: (context, vm) {
        final ref = context.ref;
        return ResponsiveListView(
          maxWidth: 860,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          tabletPadding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            _SettingsHeader(title: LocalShareCopy.settings),
            const SizedBox(height: 18),
            _SettingsSection(
              title: t.settingsTab.general.title,
              icon: Icons.palette_outlined,
              children: [
                _SettingsEntry(
                  label: t.settingsTab.general.brightness,
                  child: CustomDropdownButton<ThemeMode>(
                    value: vm.settings.theme,
                    items: vm.themeModes.map((theme) {
                      return DropdownMenuItem(
                        value: theme,
                        alignment: Alignment.center,
                        child: Text(theme.humanName),
                      );
                    }).toList(),
                    onChanged: (theme) => vm.onChangeTheme(context, theme),
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.general.color,
                  child: CustomDropdownButton<ColorMode>(
                    value: vm.settings.colorMode,
                    items: vm.colorModes.map((colorMode) {
                      return DropdownMenuItem(
                        value: colorMode,
                        alignment: Alignment.center,
                        child: Text(colorMode.humanName),
                      );
                    }).toList(),
                    onChanged: vm.onChangeColorMode,
                  ),
                ),
                _ButtonEntry(
                  label: t.settingsTab.general.language,
                  buttonLabel: vm.settings.locale?.humanName ?? t.settingsTab.general.languageOptions.system,
                  onTap: () => vm.onTapLanguage(context),
                ),
                if (checkPlatformIsDesktop()) ...[
                  /// Wayland does window position handling, so there's no need for it. See [https://github.com/localsend/localsend/issues/544]
                  if (vm.advanced && checkPlatformIsNotWaylandDesktop())
                    _BooleanEntry(
                      label: defaultTargetPlatform == TargetPlatform.windows
                          ? t.settingsTab.general.saveWindowPlacementWindows
                          : t.settingsTab.general.saveWindowPlacement,
                      value: vm.settings.saveWindowPlacement,
                      onChanged: (b) async {
                        await ref.notifier(settingsProvider).setSaveWindowPlacement(b);
                      },
                    ),
                  if (checkPlatformHasTray()) ...[
                    _BooleanEntry(
                      label: t.settingsTab.general.minimizeToTray,
                      value: vm.settings.minimizeToTray,
                      onChanged: (b) async {
                        await ref.notifier(settingsProvider).setMinimizeToTray(b);
                      },
                    ),
                  ],
                  if (checkPlatformIsDesktop()) ...[
                    _BooleanEntry(
                      label: t.settingsTab.general.launchAtStartup,
                      value: vm.autoStart,
                      onChanged: (_) => vm.onToggleAutoStart(context),
                    ),
                    Visibility(
                      visible: vm.autoStart,
                      maintainAnimation: true,
                      maintainState: true,
                      child: AnimatedOpacity(
                        opacity: vm.autoStart ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 500),
                        child: _BooleanEntry(
                          label: t.settingsTab.general.launchMinimized,
                          value: vm.autoStartLaunchHidden,
                          onChanged: (_) => vm.onToggleAutoStartLaunchHidden(context),
                        ),
                      ),
                    ),
                  ],
                  if (vm.advanced && checkPlatform([TargetPlatform.windows])) ...[
                    _BooleanEntry(
                      label: t.settingsTab.general.showInContextMenu.replaceAll('LocalSend', LocalShareCopy.appName),
                      value: vm.showInContextMenu,
                      onChanged: (_) => vm.onToggleShowInContextMenu(context),
                    ),
                  ],
                ],
                _BooleanEntry(
                  label: t.settingsTab.general.animations,
                  value: vm.settings.enableAnimations,
                  onChanged: (b) async {
                    await ref.notifier(settingsProvider).setEnableAnimations(b);
                  },
                ),
              ],
            ),
            _SettingsSection(
              title: t.settingsTab.receive.title,
              icon: Icons.download_rounded,
              children: [
                _BooleanEntry(
                  label: t.settingsTab.receive.quickSave,
                  value: vm.settings.quickSave,
                  onChanged: (b) async {
                    final old = vm.settings.quickSave;
                    await ref.notifier(settingsProvider).setQuickSave(b);
                    if (!old && b && context.mounted) {
                      await QuickSaveNotice.open(context);
                    }
                  },
                ),
                _BooleanEntry(
                  label: t.settingsTab.receive.quickSaveFromFavorites,
                  value: vm.settings.quickSaveFromFavorites,
                  onChanged: (b) async {
                    final old = vm.settings.quickSaveFromFavorites;
                    await ref.notifier(settingsProvider).setQuickSaveFromFavorites(b);
                    if (!old && b && context.mounted) {
                      await QuickSaveFromFavoritesNotice.open(context);
                    }
                  },
                ),
                _BooleanEntry(
                  label: t.settingsTab.receive.requirePin,
                  value: vm.settings.receivePin != null,
                  onChanged: (b) async {
                    final currentPIN = vm.settings.receivePin;
                    if (currentPIN != null) {
                      await ref.notifier(settingsProvider).setReceivePin(null);
                    } else {
                      final String? newPin = await showDialog<String>(
                        context: context,
                        builder: (_) => const PinDialog(
                          obscureText: false,
                          generateRandom: false,
                        ),
                      );

                      if (newPin != null && newPin.isNotEmpty) {
                        await ref.notifier(settingsProvider).setReceivePin(newPin);
                      }
                    }
                  },
                ),
                if (checkPlatformWithFileSystem())
                  _SettingsEntry(
                    label: LocalShareCopy.receiveDestination,
                    child: _SettingsActionButton(
                      label: vm.settings.destination ?? t.settingsTab.receive.downloads,
                      onPressed: () async {
                        if (vm.settings.destination != null) {
                          await ref.notifier(settingsProvider).setDestination(null);
                          if (defaultTargetPlatform == TargetPlatform.macOS) {
                            await removeExistingDestinationAccess();
                          }
                          return;
                        }

                        final directory = await pickDirectoryPath();
                        if (directory != null) {
                          if (defaultTargetPlatform == TargetPlatform.macOS) {
                            await persistDestinationFolderAccess(directory);
                          }
                          await ref.notifier(settingsProvider).setDestination(directory);
                        }
                      },
                    ),
                  ),
                if (checkPlatformWithFileSystem())
                  _SettingsEntry(
                    label: LocalShareCopy.backupDestination,
                    child: _SettingsActionButton(
                      label: vm.settings.backupDestination ?? LocalShareCopy.defaultBackupDestination,
                      onPressed: () async {
                        if (vm.settings.backupDestination != null) {
                          await ref.notifier(settingsProvider).setBackupDestination(null);
                          return;
                        }

                        final directory = await pickDirectoryPath();
                        if (directory != null) {
                          await ref.notifier(settingsProvider).setBackupDestination(directory);
                        }
                      },
                    ),
                  ),
                if (checkPlatformWithGallery())
                  _BooleanEntry(
                    label: t.settingsTab.receive.saveToGallery,
                    value: vm.settings.saveToGallery,
                    onChanged: (b) async {
                      await ref.notifier(settingsProvider).setSaveToGallery(b);
                    },
                  ),
                _BooleanEntry(
                  label: t.settingsTab.receive.autoFinish,
                  value: vm.settings.autoFinish,
                  onChanged: (b) async {
                    await ref.notifier(settingsProvider).setAutoFinish(b);
                  },
                ),
                _BooleanEntry(
                  label: t.settingsTab.receive.saveToHistory,
                  value: vm.settings.saveToHistory,
                  onChanged: (b) async {
                    await ref.notifier(settingsProvider).setSaveToHistory(b);
                  },
                ),
              ],
            ),
            if (vm.advanced)
              _SettingsSection(
                title: t.settingsTab.send.title,
                icon: Icons.send_rounded,
                children: [
                  _BooleanEntry(
                    label: t.settingsTab.send.shareViaLinkAutoAccept,
                    value: vm.settings.shareViaLinkAutoAccept,
                    onChanged: (b) async {
                      await ref.notifier(settingsProvider).setShareViaLinkAutoAccept(b);
                    },
                  ),
                ],
              ),
            _SettingsSection(
              title: t.settingsTab.network.title,
              icon: Icons.hub_outlined,
              children: [
                AnimatedCrossFade(
                  crossFadeState: vm.serverState != null &&
                          (vm.serverState!.alias != vm.settings.alias ||
                              vm.serverState!.port != vm.settings.port ||
                              vm.serverState!.https != vm.settings.https)
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topLeft,
                  firstChild: Container(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Text(t.settingsTab.network.needRestart, style: TextStyle(color: Theme.of(context).colorScheme.warning)),
                  ),
                ),
                _SettingsEntry(
                  label: '${t.settingsTab.network.server}${vm.serverState == null ? ' (${t.general.offline})' : ''}',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).inputDecorationTheme.fillColor,
                      borderRadius: Theme.of(context).inputDecorationTheme.borderRadius,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (vm.serverState == null)
                          Tooltip(
                            message: t.general.start,
                            child: TextButton(
                              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                              onPressed: () => vm.onTapStartServer(context),
                              child: const Icon(Icons.play_arrow),
                            ),
                          )
                        else
                          Tooltip(
                            message: t.general.restart,
                            child: TextButton(
                              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                              onPressed: () => vm.onTapRestartServer(context),
                              child: const Icon(Icons.refresh),
                            ),
                          ),
                        Tooltip(
                          message: t.general.stop,
                          child: TextButton(
                            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                            onPressed: vm.serverState == null ? null : vm.onTapStopServer,
                            child: const Icon(Icons.stop),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _SettingsEntry(
                  label: t.settingsTab.network.alias,
                  child: TextFieldWithActions(
                    name: t.settingsTab.network.alias,
                    controller: vm.aliasController,
                    onChanged: (s) async {
                      await ref.notifier(settingsProvider).setAlias(s);
                    },
                    actions: [
                      Tooltip(
                        message: t.settingsTab.network.generateRandomAlias,
                        child: IconButton(
                          onPressed: () async {
                            // Generates random alias
                            final newAlias = generateRandomAlias();

                            // Update the TextField with the new alias
                            vm.aliasController.text = newAlias;

                            // Persist the new alias using the settingsProvider
                            await ref.notifier(settingsProvider).setAlias(newAlias);
                          },
                          icon: const Icon(Icons.casino),
                        ),
                      ),
                      Tooltip(
                        message: t.settingsTab.network.useSystemName,
                        child: IconButton(
                          onPressed: () async {
                            // Uses dart.io to find the systems hostname
                            final newAlias = Platform.localHostname;

                            vm.aliasController.text = newAlias;
                            await ref.notifier(settingsProvider).setAlias(newAlias);
                          },
                          icon: const Icon(Icons.desktop_windows_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                if (vm.advanced)
                  _SettingsEntry(
                    label: t.settingsTab.network.deviceType,
                    child: CustomDropdownButton<DeviceType>(
                      value: vm.deviceInfo.deviceType,
                      items: DeviceType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          alignment: Alignment.center,
                          child: Icon(type.icon),
                        );
                      }).toList(),
                      onChanged: (type) async {
                        await ref.notifier(settingsProvider).setDeviceType(type);
                      },
                    ),
                  ),
                if (vm.advanced)
                  _SettingsEntry(
                    label: t.settingsTab.network.deviceModel,
                    child: TextFieldTv(
                      name: t.settingsTab.network.deviceModel,
                      controller: vm.deviceModelController,
                      onChanged: (s) async {
                        await ref.notifier(settingsProvider).setDeviceModel(s);
                      },
                    ),
                  ),
                if (vm.advanced)
                  _SettingsEntry(
                    label: t.settingsTab.network.port,
                    child: TextFieldTv(
                      name: t.settingsTab.network.port,
                      controller: vm.portController,
                      onChanged: (s) async {
                        final port = int.tryParse(s);
                        if (port != null) {
                          await ref.notifier(settingsProvider).setPort(port);
                        }
                      },
                    ),
                  ),
                if (vm.advanced)
                  _ButtonEntry(
                    label: t.settingsTab.network.network,
                    buttonLabel: switch (vm.settings.networkWhitelist != null || vm.settings.networkBlacklist != null) {
                      true => t.settingsTab.network.networkOptions.filtered,
                      false => t.settingsTab.network.networkOptions.all,
                    },
                    onTap: () async {
                      await context.push(() => const NetworkInterfacesPage());
                    },
                  ),
                if (vm.advanced)
                  _SettingsEntry(
                    label: t.settingsTab.network.discoveryTimeout,
                    child: TextFieldTv(
                      name: t.settingsTab.network.discoveryTimeout,
                      controller: vm.timeoutController,
                      onChanged: (s) async {
                        final timeout = int.tryParse(s);
                        if (timeout != null) {
                          await ref.notifier(settingsProvider).setDiscoveryTimeout(timeout);
                        }
                      },
                    ),
                  ),
                if (vm.advanced)
                  _BooleanEntry(
                    label: t.settingsTab.network.encryption,
                    value: vm.settings.https,
                    onChanged: (b) async {
                      final old = vm.settings.https;
                      await ref.notifier(settingsProvider).setHttps(b);
                      if (old && !b && context.mounted) {
                        await EncryptionDisabledNotice.open(context);
                      }
                    },
                  ),
                if (vm.advanced)
                  _SettingsEntry(
                    label: t.settingsTab.network.multicastGroup,
                    child: TextFieldTv(
                      name: t.settingsTab.network.multicastGroup,
                      controller: vm.multicastController,
                      onChanged: (s) async {
                        await ref.notifier(settingsProvider).setMulticastGroup(s);
                      },
                    ),
                  ),
                AnimatedCrossFade(
                  crossFadeState: vm.settings.port != defaultPort ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topLeft,
                  firstChild: Container(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Text(
                      t.settingsTab.network.portWarning(defaultPort: defaultPort),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  crossFadeState: vm.settings.multicastGroup != defaultMulticastGroup ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topLeft,
                  firstChild: Container(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Text(
                      t.settingsTab.network.multicastGroupWarning(defaultMulticast: defaultMulticastGroup),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
            _SettingsSection(
              title: t.settingsTab.other.title,
              icon: Icons.info_outline_rounded,
              padding: const EdgeInsets.only(bottom: 0),
              children: [
                _ButtonEntry(
                  label: _localCopy('关于 LocalShare', 'About LocalShare'),
                  buttonLabel: t.general.open,
                  onTap: () async {
                    await context.push(() => const AboutPage());
                  },
                ),
                _ButtonEntry(
                  label: _localCopy(
                    '支持上游 LocalSend 项目',
                    'Support the upstream LocalSend project',
                  ),
                  buttonLabel: _localCopy('查看', 'Open'),
                  onTap: () async {
                    await context.push(() => const DonationPage());
                  },
                ),
                _ButtonEntry(
                  label: _localCopy(
                    '上游 LocalSend 隐私政策',
                    'Upstream LocalSend privacy policy',
                  ),
                  buttonLabel: t.general.open,
                  onTap: () async {
                    await launchUrl(
                      Uri.parse('https://localsend.org/privacy'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                if (checkPlatform([TargetPlatform.iOS, TargetPlatform.macOS]))
                  _ButtonEntry(
                    label: t.settingsTab.other.termsOfUse,
                    buttonLabel: t.general.open,
                    onTap: () async {
                      await launchUrl(
                        Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _AdvancedSettingsCard(
              label: t.settingsTab.advancedSettings,
              value: vm.advanced,
              onChanged: (b) async {
                vm.onTapAdvanced(b == true);
                await ref.notifier(settingsProvider).setAdvancedSettingsEnabled(b == true);
              },
            ),
            const SizedBox(height: 20),
            _SettingsFooter(
              version: ref.watch(versionProvider).maybeWhen(
                    data: (version) => version,
                    orElse: () => null,
                  ),
              changelogLabel: t.changelogPage.title,
              onOpenChangelog: () async {
                await context.push(() => const ChangelogPage());
              },
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final String title;

  const _SettingsHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: const ValueKey('settings-compact-header'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: scheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  LocalShareCopy.appName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
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

class _SettingsEntry extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsEntry({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledTitleSize = MediaQuery.textScalerOf(context).scale(16).toDouble();
        final compact = constraints.maxWidth < 520 || scaledTitleSize > 20;
        final controlWidth = (constraints.maxWidth * 0.42).clamp(210.0, 320.0).toDouble();
        final labelWidget = Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        );

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 9 : 8,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labelWidget,
                    const SizedBox(height: 7),
                    child,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: labelWidget),
                    const SizedBox(width: 20),
                    SizedBox(width: controlWidth, child: child),
                  ],
                ),
        );
      },
    );
  }
}

/// A specialized version of [_SettingsEntry].
class _BooleanEntry extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BooleanEntry({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A specialized version of [_SettingsEntry].
class _ButtonEntry extends StatelessWidget {
  final String label;
  final String buttonLabel;
  final void Function() onTap;

  const _ButtonEntry({
    required this.label,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsEntry(
      label: label,
      child: _SettingsActionButton(label: buttonLabel, onPressed: onTap),
    );
  }
}

class _SettingsActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SettingsActionButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final EdgeInsets padding;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
    this.padding = const EdgeInsets.only(bottom: 22),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: scheme.onPrimaryContainer,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            key: ValueKey('settings-section-$title'),
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: scheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedSettingsCard extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _AdvancedSettingsCard({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: const ValueKey('advanced-settings-toggle'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
        dense: true,
        value: value,
        onChanged: (enabled) => onChanged(enabled),
        title: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            _localCopy(
              '显示端口、加密、网络接口等专业选项。',
              'Show port, encryption, and network interface options.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsFooter extends StatelessWidget {
  final String? version;
  final String changelogLabel;
  final VoidCallback onOpenChangelog;

  const _SettingsFooter({
    required this.version,
    required this.changelogLabel,
    required this.onOpenChangelog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.near_me_rounded,
                color: scheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  LocalShareCopy.appName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    if (version != null) '${_localCopy('版本', 'Version')} $version',
                    '© ${DateTime.now().year} Tien Do Nam',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        TextButton.icon(
          onPressed: onOpenChangelog,
          icon: const Icon(Icons.history_rounded, size: 18),
          label: Text(changelogLabel),
        ),
      ],
    );
  }
}

extension on ThemeMode {
  String get humanName {
    switch (this) {
      case ThemeMode.system:
        return t.settingsTab.general.brightnessOptions.system;
      case ThemeMode.light:
        return t.settingsTab.general.brightnessOptions.light;
      case ThemeMode.dark:
        return t.settingsTab.general.brightnessOptions.dark;
    }
  }
}

extension on ColorMode {
  String get humanName {
    return switch (this) {
      ColorMode.system => t.settingsTab.general.colorOptions.system,
      ColorMode.localsend => LocalShareCopy.appName,
      ColorMode.oled => t.settingsTab.general.colorOptions.oled,
      ColorMode.yaru => 'Yaru',
    };
  }
}

String _localCopy(String chinese, String english) => LocalShareCopy.isChinese ? chinese : english;
