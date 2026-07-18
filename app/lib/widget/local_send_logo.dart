import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';

/// LocalShare 品牌标记。
///
/// 类名暂时保留，避免一次性改动上游大量调用点；显示内容已经完全切换为
/// LocalShare 的图形与文案。
class LocalSendLogo extends StatelessWidget {
  final bool withText;

  const LocalSendLogo({required this.withText});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        gradient: context.localShareDesign.brandGradient,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Icon(
        Icons.near_me_rounded,
        size: 56,
        color: scheme.onPrimary,
      ),
    );

    if (withText) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          logo,
          const SizedBox(height: 20),
          Text(
            LocalShareCopy.appName,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      return logo;
    }
  }
}
