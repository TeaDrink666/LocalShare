import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:refena_flutter/refena_flutter.dart';

class DashboardPage extends StatelessWidget {
  final Future<void> Function() onOpenNativeTransfer;
  final Future<void> Function() onOpenWebTransfer;
  final Future<void> Function() onOpenBackup;

  const DashboardPage({
    required this.onOpenNativeTransfer,
    required this.onOpenWebTransfer,
    required this.onOpenBackup,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(receiveTabVmProvider);
    final scheme = Theme.of(context).colorScheme;
    final isOnline = vm.serverState != null;
    final alias = vm.serverState?.alias ?? vm.aliasSettings;

    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeHeader(
                        alias: alias,
                        isOnline: isOnline,
                        localIps: vm.localIps,
                        onOpenBackup: onOpenBackup,
                      ),
                      const SizedBox(height: 32),
                      Text(
                        LocalShareCopy.chooseMode,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        LocalShareCopy.chooseModeDescription,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const gap = 16.0;
                          final columns = constraints.maxWidth >= 980
                              ? 3
                              : constraints.maxWidth >= 620
                                  ? 2
                                  : 1;
                          final cardWidth =
                              (constraints.maxWidth - gap * (columns - 1)) /
                                  columns;
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              _ModeCard(
                                width: cardWidth,
                                icon: Icons.devices_rounded,
                                accent: scheme.primary,
                                title: LocalShareCopy.nativeTransfer,
                                description:
                                    LocalShareCopy.nativeTransferDescription,
                                onTap: onOpenNativeTransfer,
                              ),
                              _ModeCard(
                                width: cardWidth,
                                icon: Icons.language_rounded,
                                accent: scheme.tertiary,
                                title: LocalShareCopy.webTransfer,
                                description:
                                    LocalShareCopy.webTransferDescription,
                                onTap: onOpenWebTransfer,
                              ),
                              _ModeCard(
                                width: cardWidth,
                                icon: Icons.photo_library_rounded,
                                accent: const Color(0xfff28c45),
                                title: LocalShareCopy.phoneBackup,
                                description:
                                    LocalShareCopy.phoneBackupDescription,
                                onTap: onOpenBackup,
                                badge: LocalShareCopy.phoneBackupBadge,
                                cardKey:
                                    const Key('dashboard-phone-backup-card'),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: scheme.outlineVariant.withOpacity(0.55)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(Icons.shield_outlined,
                                  color: scheme.onPrimaryContainer),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    LocalShareCopy.privacyNoticeTitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    LocalShareCopy.privacyNoticeDescription,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
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
      ],
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  final String alias;
  final bool isOnline;
  final List<String> localIps;
  final Future<void> Function() onOpenBackup;

  const _WelcomeHeader(
      {required this.alias,
      required this.isOnline,
      required this.localIps,
      required this.onOpenBackup});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.58)!,
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            isOnline ? const Color(0xff9ff5c2) : Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isOnline ? LocalShareCopy.ready : LocalShareCopy.offline,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                LocalShareCopy.welcomeTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                alias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white.withOpacity(0.92)),
              ),
              const SizedBox(height: 6),
              Text(
                localIps.isEmpty
                    ? LocalShareCopy.localNetwork
                    : localIps.join('  ·  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white.withOpacity(0.7)),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                key: const Key('dashboard-backup-shortcut'),
                onPressed: onOpenBackup,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withOpacity(0.14),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.white.withOpacity(0.22)),
                  ),
                ),
                icon: const Icon(Icons.photo_library_rounded, size: 20),
                label: Text(LocalShareCopy.phoneBackup),
              ),
            ],
          );

          if (compact) {
            return content;
          }

          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 24),
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: const Icon(Icons.near_me_rounded,
                    size: 62, color: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  final double width;
  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final Future<void> Function() onTap;
  final String? badge;
  final Key? cardKey;

  const _ModeCard({
    required this.width,
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
    this.cardKey,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        key: widget.cardKey,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: widget.width,
        constraints: const BoxConstraints(minHeight: 238),
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: _hovered
                  ? widget.accent.withOpacity(0.45)
                  : scheme.outlineVariant.withOpacity(0.55)),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? widget.accent.withOpacity(0.13)
                  : Colors.black.withOpacity(0.035),
              blurRadius: _hovered ? 24 : 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: widget.accent.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 27),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (widget.badge != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: widget.accent.withOpacity(0.11),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.badge!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: widget.accent,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    widget.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        LocalShareCopy.open,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: widget.accent, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded,
                          size: 18, color: widget.accent),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
