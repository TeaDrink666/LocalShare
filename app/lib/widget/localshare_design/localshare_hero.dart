import 'package:flutter/material.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';

/// Unified gradient hero used by dashboard, web transfer, history and other
/// top-level pages. Converges the previously divergent gradient heroes into
/// one visual primitive so every page shares the same brand feel.
class LocalShareHero extends StatelessWidget {
  const LocalShareHero({
    required this.title,
    this.subtitle,
    this.icon,
    this.badge,
    this.leading,
    this.trailing,
    this.content,
    this.padding = const EdgeInsets.all(LocalShareSpacing.lg),
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? badge;
  final Widget? leading;
  final Widget? trailing;
  final Widget? content;
  final EdgeInsetsGeometry padding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final design = context.localShareDesign;
    final isDark = scheme.brightness == Brightness.dark;

    final iconWidget = leading ??
        (icon == null
            ? null
            : Container(
                width: compact ? 56 : 64,
                height: compact ? 56 : 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(compact ? 18 : 20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Icon(icon, color: Colors.white, size: compact ? 28 : 32),
              ));

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: design.heroGradient,
        borderRadius: BorderRadius.circular(compact ? LocalShareRadii.extraLarge : LocalShareRadii.hero),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(isDark ? 0.3 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final titleColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null) ...[
                badge!,
                const SizedBox(height: LocalShareSpacing.md),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: LocalShareSpacing.xs),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withOpacity(0.82),
                        height: 1.45,
                      ),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: LocalShareSpacing.md),
                content!,
              ],
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (iconWidget != null) ...[
                  iconWidget,
                  const SizedBox(height: LocalShareSpacing.md),
                ],
                titleColumn,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (iconWidget != null) ...[
                iconWidget,
                const SizedBox(width: LocalShareSpacing.lg),
              ],
              Expanded(child: titleColumn),
              if (trailing != null) ...[
                const SizedBox(width: LocalShareSpacing.md),
                trailing!,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Small translucent status pill placed inside a [LocalShareHero].
class LocalShareHeroBadge extends StatelessWidget {
  const LocalShareHeroBadge({required this.label, this.dotColor});

  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(LocalShareRadii.full),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor ?? const Color(0xff9ff5c2),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A clean card container used across sections. Borderless, quiet, with a
/// subtle surface tint - keeps the modern minimal look.
class LocalShareCard extends StatelessWidget {
  const LocalShareCard({
    required this.child,
    this.padding = const EdgeInsets.all(LocalShareSpacing.md),
    this.margin = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(LocalShareRadii.large)),
    this.onTap,
    this.semanticLabel,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.surfaceContainerLow;

    Widget content = Ink(
      decoration: ShapeDecoration(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        hoverColor: scheme.primary.withOpacity(0.05),
        highlightColor: scheme.primary.withOpacity(0.05),
        splashColor: scheme.primary.withOpacity(0.07),
        child: Padding(padding: padding, child: child),
      ),
    );

    final card = Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );

    if (semanticLabel == null) {
      return card;
    }
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: card,
    );
  }
}
