import 'package:flutter/material.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';

/// Standard section heading used above device, transfer and backup groups.
class LocalShareSectionHeader extends StatelessWidget {
  const LocalShareSectionHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.action,
    this.padding = const EdgeInsets.symmetric(horizontal: LocalShareSpacing.xs),
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            IconTheme.merge(
              data: IconThemeData(color: theme.colorScheme.primary, size: 22),
              child: leading!,
            ),
            const SizedBox(width: LocalShareSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: LocalShareSpacing.xxs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(width: LocalShareSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}
