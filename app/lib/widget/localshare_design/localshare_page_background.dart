import 'package:flutter/material.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';

/// A very quiet brand wash intended for top-level app pages.
///
/// The gradient is deliberately subtle so file names, progress indicators and
/// device states remain the visual priority.
class LocalSharePageBackground extends StatelessWidget {
  const LocalSharePageBackground({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration:
          BoxDecoration(gradient: context.localShareDesign.pageGradient),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
