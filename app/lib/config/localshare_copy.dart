import 'package:localsend_app/gen/strings.g.dart';

/// Product copy that is specific to the LocalShare fork.
///
/// Keeping this small layer separate lets the first development milestones
/// move without regenerating every upstream LocalSend locale. Once the new
/// flows settle, these strings can move into the regular slang catalogs.
abstract final class LocalShareCopy {
  static bool get _isChinese => switch (LocaleSettings.currentLocale) {
        AppLocale.zhCn || AppLocale.zhHk || AppLocale.zhTw => true,
        _ => false,
      };

  /// 新设计页面在上游多语言目录完成迁移前使用的语言判断。
  static bool get isChinese => _isChinese;

  static String get appName => 'LocalShare';
  static String get home => _isChinese ? '首页' : 'Home';
  static String get receive => _isChinese ? '接收' : 'Receive';
  static String get send => _isChinese ? '发送' : 'Send';
  static String get backup => _isChinese ? '备份' : 'Backup';
  static String get settings => _isChinese ? '设置' : 'Settings';
  static String get dropToSend =>
      _isChinese ? '松开即可添加到发送列表' : 'Drop to add items';
  static String get welcomeTitle =>
      _isChinese ? '文件传输，就该这么简单' : 'File transfer, made effortless';
  static String get welcomeSubtitle => _isChinese
      ? '在你的局域网内高速传输，数据不经过云端。'
      : 'Move files at full LAN speed without sending your data through the cloud.';
  static String get ready => _isChinese ? '已就绪' : 'Ready';
  static String get offline => _isChinese ? '离线' : 'Offline';
  static String get localNetwork => _isChinese ? '本地网络' : 'Local network';

  static String get chooseMode =>
      _isChinese ? '今天想怎么传？' : 'How would you like to transfer?';
  static String get chooseModeDescription => _isChinese
      ? '客户端互传、免安装网页传输和手机增量备份，都从这里开始。'
      : 'Start a client transfer, a browser transfer, or an incremental phone backup.';
  static String get nativeTransfer => _isChinese ? '设备互传' : 'Device transfer';
  static String get nativeTransferDescription => _isChinese
      ? '使用客户端自动发现设备，适合日常高速互传。'
      : 'Discover nearby clients automatically for fast everyday transfers.';
  static String get webTransfer => _isChinese ? '网页传输' : 'Web transfer';
  static String get webTransferDescription => _isChinese
      ? '通过链接或二维码收发文件，对方无需安装客户端。'
      : 'Share through a link or QR code when the other device has no client.';
  static String get phoneBackup => _isChinese ? '手机备份' : 'Phone backup';
  static String get phoneBackupDescription => _isChinese
      ? '手动备份 Android 中的照片和视频，后续只传新增内容。'
      : 'Manually back up Android photos and videos, then send only new items.';
  static String get phoneBackupBadge =>
      _isChinese ? 'Android 手动增量备份' : 'Manual Android incremental backup';
  static String get privacyNoticeTitle =>
      _isChinese ? '只在你的局域网内传输' : 'Transfers stay on your LAN';
  static String get privacyNoticeDescription => _isChinese
      ? '不上传云端；接收文件仍需你的确认。'
      : 'Nothing is uploaded to the cloud, and incoming files still require approval.';
  static String get open => _isChinese ? '打开' : 'Open';

  static String get webPageTitle => _isChinese ? '网页传输' : 'Web transfer';
  static String get webPageSubtitle => _isChinese
      ? '让没有安装 LocalShare 的设备也能参与传输。'
      : 'Share with devices that do not have LocalShare installed.';
  static String get sendToBrowser =>
      _isChinese ? '发送到浏览器' : 'Send to a browser';
  static String get sendToBrowserDescription => _isChinese
      ? '选择文件后生成局域网链接和二维码。'
      : 'Select files and create a local link and QR code.';
  static String get uploadFromBrowser =>
      _isChinese ? '从浏览器上传' : 'Upload from a browser';
  static String get uploadFromBrowserDescription => _isChinese
      ? '浏览器选择文件后上传到当前设备。'
      : 'Choose files in a browser and upload them to this device.';
  static String get openUploadPortal =>
      _isChinese ? '开启网页接收' : 'Open web receiver';
  static String get webReceiveTitle =>
      _isChinese ? '从网页接收' : 'Receive from the web';
  static String get webReceiveSubtitle => _isChinese
      ? '在另一台设备的浏览器中打开下方地址，即可向当前设备发送文件。'
      : 'Open one of these addresses in another device\'s browser to send files here.';
  static String get waitingForBrowser =>
      _isChinese ? '等待浏览器连接' : 'Waiting for a browser';
  static String get webReceiveSecurity => _isChinese
      ? '文件仍会经过原有的接收确认流程，未经同意不会写入设备。'
      : 'Files still go through the normal approval flow and are never saved without your consent.';
  static String get planned => _isChinese ? '开发中' : 'In development';
  static String get selectFiles => _isChinese ? '选择文件' : 'Select files';
  static String get createLink => _isChinese ? '生成网页链接' : 'Create web link';
  static String get selectedItems => _isChinese ? '已选内容' : 'Selected items';
  static String get clearSelection => _isChinese ? '清空' : 'Clear';
  static String get continueInClient =>
      _isChinese ? '使用客户端发送' : 'Send with the client';

  static String get backupPageTitle =>
      _isChinese ? '手机媒体备份' : 'Phone media backup';
  static String get backupPageSubtitle => _isChinese
      ? '手动扫描照片和视频，只发送这台电脑尚未确认的新内容。'
      : 'Scan photos and videos manually, then send only items this computer has not confirmed.';
  static String get backupPreview => _isChinese ? '增量备份' : 'Incremental backup';
  static String get backupPreviewDescription => _isChinese
      ? '每台电脑独立记录；Windows 完整落盘并自动回执后，内容才会标记为已备份。'
      : 'History is separate for every computer. Items count as backed up only after Windows verifies and acknowledges them.';
  static String get choosePhotos =>
      _isChinese ? '选择照片和视频' : 'Choose photos and videos';
  static String get backupViaWeb =>
      _isChinese ? '通过网页备份' : 'Back up through the web';
  static String get backupViaClient =>
      _isChinese ? '发送到 Windows 客户端' : 'Send to the Windows client';
  static String get nearbyComputers => _isChinese ? '附近设备' : 'Nearby devices';
  static String get refreshNearbyDevices =>
      _isChinese ? '重新扫描附近设备' : 'Scan nearby devices again';
  static String get findingNearbyDevices =>
      _isChinese ? '正在查找同一局域网内的设备…' : 'Finding devices on this LAN…';
  static String get noNearbyComputers =>
      _isChinese ? '暂时没有发现设备' : 'No nearby devices found';
  static String get manualConnection =>
      _isChinese ? '手动连接' : 'Connect manually';
  static String get backupViaLink => _isChinese ? '通过链接发送' : 'Send with a link';
  static String get backupViaLinkDescription => _isChinese
      ? '生成局域网链接或二维码，电脑无需安装软件'
      : 'Create a LAN link or QR code; no app is required on the computer';
  static String get startOnAndroid => _isChinese
      ? '请在 Android 手机上发起备份，Windows 会作为接收端。'
      : 'Start the backup on Android; Windows will act as the receiver.';
  static String get goToReceive => _isChinese ? '进入接收页' : 'Open receive page';

  static String get backupTarget => _isChinese ? '备份目标' : 'Backup target';
  static String get backupTargetDescription => _isChinese
      ? '为每台电脑建立独立档案，换电脑时不会混用备份记录。'
      : 'Each computer has a separate profile, so backup history never gets mixed.';
  static String get defaultBackupTarget =>
      _isChinese ? '我的 Windows 电脑' : 'My Windows PC';
  static String get addBackupTarget => _isChinese ? '添加电脑' : 'Add computer';
  static String get newBackupTarget =>
      _isChinese ? '新建备份目标' : 'New backup target';
  static String get computerName => _isChinese ? '电脑名称' : 'Computer name';
  static String get cancel => _isChinese ? '取消' : 'Cancel';
  static String get create => _isChinese ? '创建' : 'Create';
  static String get mediaScope => _isChinese ? '扫描内容' : 'Media to scan';
  static String get photos => _isChinese ? '照片' : 'Photos';
  static String get videos => _isChinese ? '视频' : 'Videos';
  static String get scanForChanges =>
      _isChinese ? '扫描新增内容' : 'Scan for new items';
  static String scanningItems(int count) =>
      _isChinese ? '正在扫描，已发现 $count 项' : 'Scanning · $count items found';
  static String get mediaPermissionDenied => _isChinese
      ? '需要照片和视频读取权限才能建立备份清单。请授权后重试。'
      : 'Photo and video read access is required to build a backup inventory.';
  static String get limitedMediaAccess => _isChinese
      ? '系统只允许访问部分照片，本次扫描结果可能不完整。'
      : 'Android granted access to selected media only, so this scan may be incomplete.';
  static String get scanFailed => _isChinese ? '扫描失败' : 'Scan failed';
  static String get backupStorageUnavailable => _isChinese
      ? '无法打开备份记录存储。扫描和备份功能已停用，请重试。'
      : 'Backup storage could not be opened. Scanning and backup are disabled until you retry.';
  static String get backupReady => _isChinese ? '本次待备份' : 'Ready to back up';
  static String get everythingBackedUp =>
      _isChinese ? '没有发现需要备份的新内容' : 'Everything is already backed up';
  static String get everythingBackedUpDescription => _isChinese
      ? '所选类型中当前可访问的内容，都已在这台电脑的确认记录中。'
      : 'All currently visible items in the selected types are in this computer\'s confirmed history.';
  static String get newItems => _isChinese ? '新增' : 'New';
  static String get changedItems => _isChinese ? '有变化' : 'Changed';
  static String get alreadyBackedUp => _isChinese ? '已备份' : 'Backed up';
  static String get transferSize => _isChinese ? '传输大小' : 'Transfer size';
  static String get pendingConfirmation =>
      _isChinese ? '网页备份待确认' : 'Web backup awaiting confirmation';
  static String pendingConfirmationDescription(int count) => _isChinese
      ? '浏览器无法报告最终保存目录。请在电脑上核对这 $count 项后再确认。'
      : 'A browser cannot report its final save folder. Verify these $count ${count == 1 ? 'item' : 'items'} on the computer before confirming.';
  static String get pendingComputerReceipt =>
      _isChinese ? '等待电脑自动核验' : 'Waiting for computer verification';
  static String pendingComputerReceiptDescription(int count) => _isChinese
      ? '还有 $count 项未收到 Windows 的完整落盘回执；选择附近电脑即可继续，成功项目会自动记账。'
      : '$count ${count == 1 ? 'item has' : 'items have'} no durable Windows receipt yet. Select the nearby computer to resume; verified items are recorded automatically.';
  static String get confirmSaved =>
      _isChinese ? '确认电脑已保存' : 'Confirm files are saved';
  static String get discardPending =>
      _isChinese ? '取消这批记录' : 'Discard pending batch';
  static String get pendingBatchChanged => _isChinese
      ? '部分照片或视频在准备后发生了变化。请取消这批记录，然后重新扫描。'
      : 'Some photos or videos changed after this batch was prepared. Discard the batch and scan again.';
  static String backupTargetMismatch(String profile, String device) => _isChinese
      ? '“$profile”属于另一台电脑，不能发送到“$device”。请在上方切换或新建备份目标后重新扫描。'
      : '“$profile” belongs to another computer and cannot be sent to “$device”. Switch or create a backup target above, then scan again.';
  static String deviceAlreadyHasBackupTarget(String device, String profile) =>
      _isChinese
          ? '“$device”已经使用备份目标“$profile”。请先在上方切换到该目标并重新扫描。'
          : '“$device” already uses the “$profile” backup target. Select it above and scan again.';
  static String get confirmSavedTitle => _isChinese
      ? '确认目标电脑已完整保存？'
      : 'Confirm the target computer saved everything?';
  static String get confirmSavedMessage => _isChinese
      ? '只有当电脑端的文件已经完整保存时才确认。确认后，下次扫描会跳过这批内容。'
      : 'Confirm only after the files are fully saved on the computer. The next scan will then skip this batch.';
  static String get confirmationTargetComputer =>
      _isChinese ? '目标电脑' : 'Target computer';
  static String get confirmationItemCount => _isChinese ? '项目数' : 'Items';
  static String get confirmationTotalSize => _isChinese ? '总大小' : 'Total size';
  static String get savingBackupState =>
      _isChinese ? '正在保存备份状态，请稍候…' : 'Saving backup status. Please wait…';
  static String get confirm => _isChinese ? '确认' : 'Confirm';
  static String confirmedItems(int count) =>
      _isChinese ? '已确认 $count 项备份' : 'Confirmed $count backed-up items';
  static String get lastConfirmed => _isChinese ? '上次确认' : 'Last confirmed';
  static String get neverConfirmed => _isChinese ? '尚未备份' : 'No backup yet';
  static String get preparingBackup =>
      _isChinese ? '正在准备备份清单…' : 'Preparing backup manifest…';
  static String get startBackupHint => _isChinese
      ? 'Windows 会在文件完整落盘后自动确认，失败项目会保留到下次重试。'
      : 'Windows confirms files automatically after durable storage; failed items remain for the next retry.';
  static String get verifyingBackupReceipt => _isChinese
      ? '正在等待电脑核验并写入备份回执…'
      : 'Waiting for the computer to verify files and save the receipt…';
  static String computerVerifiedItems(int confirmed, int remaining) => _isChinese
      ? '电脑已确认 $confirmed 项${remaining == 0 ? '，本次备份完成' : '，还有 $remaining 项可重试'}'
      : 'Computer verified $confirmed ${confirmed == 1 ? 'item' : 'items'}${remaining == 0 ? '; backup complete' : '; $remaining remaining'}';
  static String get backupProtocolUnavailable => _isChinese
      ? '目标电脑不支持自动备份回执，请更新并运行最新版 LocalShare Windows 客户端。'
      : 'The target computer does not support automatic backup receipts. Update and run the latest LocalShare Windows client.';
  static String get retry => _isChinese ? '重试' : 'Retry';
  static String get openSettings =>
      _isChinese ? '打开系统设置' : 'Open system settings';
  static String get noVisibleMedia =>
      _isChinese ? '没有发现可访问的媒体' : 'No visible media found';
  static String get noVisibleMediaDescription => _isChinese
      ? '当前授权范围和所选类型中没有可扫描的照片或视频。'
      : 'No photos or videos are visible in the selected types and current permission scope.';
  static String get replaceSelectionTitle =>
      _isChinese ? '替换当前发送列表？' : 'Replace the current send list?';
  static String replaceSelectionMessage(int count) => _isChinese
      ? '设备互传中已有 $count 项选择。继续会用本次备份内容替换它们。'
      : 'Device transfer already has $count selected items. Continuing will replace them with this backup batch.';
  static String get replace => _isChinese ? '替换' : 'Replace';

  static String itemCount(int count) =>
      _isChinese ? '$count 个项目' : '$count ${count == 1 ? 'item' : 'items'}';
}
