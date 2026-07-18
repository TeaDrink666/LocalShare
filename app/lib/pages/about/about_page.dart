import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/debug/debug_page.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/localshare_design/localshare_design.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

part 'contributors.dart';

part 'packagers.dart';

part 'translators.dart';

final _translatorWithGithubRegex = RegExp(r'(.+) \(@([\w\-_]+)\)');

class AboutPage extends StatelessWidget {
  const AboutPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isChinese = LocalShareCopy.isChinese;
    return Scaffold(
      appBar: AppBar(
        title: Text(isChinese ? '关于 LocalShare' : 'About LocalShare'),
      ),
      body: LocalSharePageBackground(
        child: ResponsiveListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
          children: [
            const LocalSendLogo(withText: true),
            const SizedBox(height: 12),
            Text(
              isChinese
                  ? '为 Windows 与 Android 打造的局域网传输工具'
                  : 'LAN transfer designed for Windows and Android',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            LocalShareSurface(
              style: LocalShareSurfaceStyle.tinted,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isChinese ? '这个版本' : 'This edition',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isChinese
                        ? 'LocalShare 在 LocalSend 的可靠传输能力上，加入了免安装网页收发、二维码链接和 Android 照片视频手动增量备份，并重新设计了主要界面。所有传输都由你在局域网内发起。'
                        : 'LocalShare builds on LocalSend with browser transfers, QR links, manual incremental Android media backup, and a redesigned primary experience. Transfers remain under your control on the local network.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LocalShareSurface(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.code_rounded, color: primaryColor),
                      const SizedBox(width: 10),
                      Text(
                        isChinese ? '开源与上游项目' : 'Open source and upstream',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isChinese
                        ? '本项目基于 LocalSend v1.17.0 开发。感谢原作者 Tien Do Nam、贡献者、打包者和翻译者；上游项目采用 Apache License 2.0。'
                        : 'This project is based on LocalSend v1.17.0. Thanks to Tien Do Nam and all upstream contributors, packagers, and translators. The upstream project uses Apache License 2.0.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async => launchUrl(
                          Uri.parse('https://github.com/localsend/localsend'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(isChinese ? '上游源代码' : 'Upstream source'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async => launchUrl(
                          Uri.parse(
                              'https://www.apache.org/licenses/LICENSE-2.0'),
                        ),
                        icon: const Icon(Icons.gavel_rounded, size: 18),
                        label: const Text('Apache License 2.0'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async =>
                            context.push(() => const LicensePage()),
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        label: Text(isChinese ? '依赖许可' : 'License notices'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LocalShareSurface(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                leading: const Icon(Icons.volunteer_activism_rounded),
                title: Text(isChinese ? '上游项目致谢' : 'Upstream credits'),
                subtitle: Text(
                  isChinese
                      ? '查看作者、贡献者与翻译者'
                      : 'Authors, contributors, and translators',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.aboutPage.author, style: theme.textTheme.titleSmall),
                  Text.rich(_buildContributor(
                    label: 'Tien Do Nam (@Tienisto)',
                    primaryColor: primaryColor,
                  )),
                  const SizedBox(height: 16),
                  Text(t.aboutPage.contributors,
                      style: theme.textTheme.titleSmall),
                  ..._contributors.map(
                    (contributor) => Text.rich(_buildContributor(
                      label: contributor,
                      primaryColor: primaryColor,
                    )),
                  ),
                  const SizedBox(height: 16),
                  Text(t.aboutPage.packagers,
                      style: theme.textTheme.titleSmall),
                  _CreditsTable(
                    rows: _packagers.map((key, value) => MapEntry(key, value)),
                    primaryColor: primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(t.aboutPage.translators,
                      style: theme.textTheme.titleSmall),
                  _CreditsTable(
                    rows: _translators.map(
                      (key, value) => MapEntry(key.translations.locale, value),
                    ),
                    primaryColor: primaryColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LocalShareSurface(
              onTap: () async => context.push(() => const DebugPage()),
              child: Row(
                children: [
                  Icon(Icons.troubleshoot_rounded, color: primaryColor),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isChinese ? '诊断工具' : 'Diagnostics',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          isChinese
                              ? '查看网络发现、安全与运行日志'
                              : 'Inspect discovery, security, and runtime logs',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditsTable extends StatelessWidget {
  const _CreditsTable({required this.rows, required this.primaryColor});

  final Map<String, List<String>> rows;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: rows.entries
          .map(
            (entry) => TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 14, top: 4),
                  child: Text(entry.key),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text.rich(
                    TextSpan(
                      children: entry.value
                          .mapIndexed(
                            (index, contributor) => _buildContributor(
                              label: contributor,
                              primaryColor: primaryColor,
                              newLine: index != 0,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}

/// Displays the contributor name and links to their github profile.
InlineSpan _buildContributor(
    {required String label,
    required Color primaryColor,
    bool newLine = false}) {
  final newLineStr = newLine ? '\n' : '';

  if (label.startsWith('@')) {
    // Only github name
    return TextSpan(
      text: '$newLineStr$label',
      style: TextStyle(color: primaryColor),
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          await launchUrl(Uri.parse('https://github.com/${label.substring(1)}'),
              mode: LaunchMode.externalApplication);
        },
    );
  }

  final match = _translatorWithGithubRegex.firstMatch(label);
  if (match != null) {
    // Full name and github name
    final fullName = match.group(1)!;
    final githubName = match.group(2)!;
    return TextSpan(
      children: [
        TextSpan(text: '$newLineStr$fullName'),
        const TextSpan(text: ' '),
        TextSpan(
          text: '@$githubName',
          style: TextStyle(color: primaryColor),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              await launchUrl(Uri.parse('https://github.com/$githubName'),
                  mode: LaunchMode.externalApplication);
            },
        ),
      ],
    );
  }

  // Only full name
  return TextSpan(text: '$newLineStr$label');
}
