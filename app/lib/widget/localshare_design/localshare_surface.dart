import 'package:flutter/material.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';

enum LocalShareSurfaceStyle {
  standard,
  subtle,
  tinted,
  accent,
}

/// A consistent card/surface primitive for transfer tiles, backup summaries,
/// empty states and dashboard sections.
class LocalShareSurface extends StatelessWidget {
  const LocalShareSurface({
    required this.child,
    this.style = LocalShareSurfaceStyle.standard,
    this.padding = const EdgeInsets.all(LocalShareSpacing.md),
    this.margin = EdgeInsets.zero,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(LocalShareRadii.large)),
    this.onTap,
    this.semanticLabel,
    this.elevation,
    super.key,
  });

  final Widget child;
  final LocalShareSurfaceStyle style;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double? elevation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final design = context.localShareDesign;
    final isDark = colors.brightness == Brightness.dark;

    final (
      Color background,
      Gradient? gradient,
      Color foreground,
      Color border
    ) = switch (style) {
      LocalShareSurfaceStyle.standard => (
          design.surfaceRaised,
          null,
          colors.onSurface,
          colors.outlineVariant.withOpacity(isDark ? 0.55 : 0.7),
        ),
      LocalShareSurfaceStyle.subtle => (
          Color.alphaBlend(colors.primary.withOpacity(isDark ? 0.055 : 0.035),
              colors.surface),
          null,
          colors.onSurface,
          colors.outlineVariant.withOpacity(0.45),
        ),
      LocalShareSurfaceStyle.tinted => (
          colors.primaryContainer.withOpacity(isDark ? 0.52 : 0.64),
          null,
          colors.onPrimaryContainer,
          colors.primary.withOpacity(isDark ? 0.28 : 0.18),
        ),
      LocalShareSurfaceStyle.accent => (
          colors.primary,
          design.brandGradient,
          colors.onPrimary,
          Colors.white.withOpacity(isDark ? 0.12 : 0.2),
        ),
    };

    final resolvedElevation = elevation ??
        (style == LocalShareSurfaceStyle.standard ? (isDark ? 0 : 1) : 0);
    final shape = RoundedRectangleBorder(
      borderRadius: borderRadius,
      side: BorderSide(color: border),
    );

    Widget content = Ink(
      decoration: ShapeDecoration(
        color: gradient == null ? background : null,
        gradient: gradient,
        shape: shape,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        hoverColor: foreground.withOpacity(0.055),
        highlightColor: foreground.withOpacity(0.06),
        splashColor: foreground.withOpacity(0.09),
        child: Padding(
          padding: padding,
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground),
              child: child,
            ),
          ),
        ),
      ),
    );

    content = Material(
      color: Colors.transparent,
      elevation: resolvedElevation,
      shadowColor: colors.shadow.withOpacity(isDark ? 0.3 : 0.1),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (semanticLabel != null || onTap != null) {
      content = Semantics(
        label: semanticLabel,
        button: onTap != null,
        child: content,
      );
    }

    return Padding(
      padding: margin,
      child: content,
    );
  }
}
