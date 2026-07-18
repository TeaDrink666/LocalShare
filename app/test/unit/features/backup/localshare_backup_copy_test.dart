import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:test/test.dart';

void main() {
  late AppLocale previousLocale;

  setUp(() {
    previousLocale = LocaleSettings.currentLocale;
  });

  tearDown(() async {
    await LocaleSettings.setLocale(previousLocale);
  });

  test('pending copy distinguishes automatic and web verification', () async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    expect(LocalShareCopy.pendingComputerReceipt, '等待电脑自动核验');
    expect(
      LocalShareCopy.pendingComputerReceiptDescription(3),
      allOf(contains('Windows'), contains('成功项目会自动记账')),
    );
    expect(LocalShareCopy.pendingConfirmation, '网页备份待确认');
    expect(
      LocalShareCopy.pendingConfirmationDescription(3),
      allOf(contains('浏览器'), contains('在电脑上核对')),
    );

    await LocaleSettings.setLocale(AppLocale.en);
    expect(
      LocalShareCopy.pendingComputerReceipt,
      'Waiting for computer verification',
    );
    expect(
      LocalShareCopy.pendingComputerReceiptDescription(3),
      allOf(contains('Windows receipt'), contains('recorded automatically')),
    );
    expect(LocalShareCopy.pendingConfirmation, contains('Web backup'));
    expect(
      LocalShareCopy.pendingConfirmationDescription(3),
      allOf(contains('browser'), contains('computer before confirming')),
    );
  });

  test('confirmation labels name every safety-critical detail', () async {
    await LocaleSettings.setLocale(AppLocale.zhCn);
    expect(LocalShareCopy.confirmationTargetComputer, '目标电脑');
    expect(LocalShareCopy.confirmationItemCount, '项目数');
    expect(LocalShareCopy.confirmationTotalSize, '总大小');

    await LocaleSettings.setLocale(AppLocale.en);
    expect(LocalShareCopy.confirmationTargetComputer, 'Target computer');
    expect(LocalShareCopy.confirmationItemCount, 'Items');
    expect(LocalShareCopy.confirmationTotalSize, 'Total size');
  });
}
