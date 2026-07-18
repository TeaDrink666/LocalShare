# LocalShare 架构

- 状态：实现蓝图
- 基线：LocalSend `v1.17.0` (`7f21d1f`)
- 主要平台：Windows 和 Android

## 1. 产品约定

LocalShare 具备三项用户可见能力，而非只有一种传输模式：

1. **原生应用间传输**：在 LocalShare 客户端之间传输。继续保留 LocalSend 现有的设备发现、请求批准、加密传输、进度显示和重试行为。
2. **网页传输**：作为额外通道：
   - 应用 -> 浏览器下载，通过临时链接或二维码；
   - 浏览器 -> 应用上传，通过临时链接或二维码。
3. **Android 媒体手动备份**：备份到一个已命名的 Windows 目标。目标可以是 Windows LocalShare 客户端（完整增量模式），也可以是浏览器（零安装备用方案，需要用户明确手动确认）。

只有选择网页通道时，接收端才不需要安装应用。原生传输仍要求两端都安装 LocalShare。

首个版本不包含以下目标：定时/后台备份、云中继、互联网传输、账号登录、删除同步，以及让浏览器在用户无感知的情况下写入任意 Windows 文件夹。

## 2. 基线概览：v1.17.0 当前实现

| 区域 | 当前集成点 | 当前行为/约束 |
| --- | --- | --- |
| 应用根节点 | `app/lib/main.dart` | 构建 `LocalSendApp`；从 `HomeTab.send` 启动。 |
| 导航 | `app/lib/pages/home_page.dart`, `app/lib/pages/home_page_controller.dart` | `HomeTab.send/receive/backup/settings` 以固定顺序映射到不可滚动的 `PageView`、`NavigationRail` 和移动端 `NavigationBar`。 |
| 选择 | `app/lib/provider/selection/selected_sending_files_provider.dart` | 持有所选的 `CrossFile` 对象；目录会转换为相对文件名。 |
| 原生发送端 | `app/lib/provider/network/send_provider.dart` | 调用 LocalSend v1/v2 `prepare-upload`，接收每个文件对应的令牌，然后通过工作 isolate 流式上传。 |
| 原生接收端 | `app/lib/provider/network/server/controller/receive_controller.dart` | 注册 info/register/prepare-upload/upload/cancel/show 路由，并持有一个 `ReceiveSessionState`。上传响应会在 `saveFile` 完成后返回。 |
| 原生服务器 | `app/lib/provider/network/server/server_provider.dart` | 持有一个 `HttpServer`、一个原生接收会话和当前的 `WebSendState`。它在配置的原生端口上绑定 `0.0.0.0`。 |
| 网页入口 | `app/lib/pages/tabs/send_tab_vm.dart` | 隐藏的 `SendMode.link` 菜单操作会打开 `WebSendPage`；它不会作为真正的发送模式持久化。 |
| 应用 -> 浏览器 | `app/lib/pages/web_send_page.dart`, `app/lib/provider/network/server/controller/send_controller.dart` | 重启单例服务器，提供网页，等待主机批准，然后为每个文件开放一个 GET。 |
| 浏览器客户端 | `app/assets/web/index.html`, `app/assets/web/main.js` | 旧式 JavaScript；仅支持应用 -> 浏览器下载；不支持上传、Range、文件夹结构保留、聚合进度或可靠的会话身份标识。 |
| HTTP 抽象 | `app/lib/util/simple_server.dart` | 仅支持精确路径的 GET/POST 路由；不支持路径参数、中间件、HEAD/PUT/DELETE、集中式错误处理或流式二进制资源辅助方法。 |
| 媒体访问 | `wechat_assets_picker`, `CrossFileConverters.convertAssetEntity` | 适合交互式选择，但没有分页的 MediaStore 清单，也没有按目标持久化的备份台账。 |
| 持久化 | `app/lib/provider/persistence_provider.dart` | SharedPreferences/设置 JSON。适用于设置，不适合数万条媒体记录或运行日志。 |

必须保留的重要基线行为：

- `common/lib/api_route_builder.dart` 和现有 DTO 是 LocalSend 兼容协议。
- 原生发送使用 `CrossFile -> FileDto -> SendingFile`；Android `content://` 流会在上传 isolate 中解析。
- 原生接收端仅在目标写入完成后返回成功，因此成功的原生文件请求是有意义的持久化确认。
- 目录名已经通过 `FileDto.fileName` 中的 `/` 表示，并由原生接收端安全地落地为实际目录。

新路径中必须移除的重要基线行为：

- `WebSendPage._init` 会停止常规原生服务器，并以临时 HTTP/HTTPS 设置重新启动。离开页面时还会再次重启。因此，网页共享会中断原生可用性。
- 网页会话 ID 当前使用远程 IP 地址。同一设备上的两个标签页或用户会发生冲突，而且 IP 地址不是授权凭据。
- 整个 `WebSendState` 与 `ServerState` 耦合；设备发现中的 `download` 标志也从该状态推断。
- 网页下载总是返回 `200` 并从第 0 字节开始传输。尚未实现 Android `content://` 的范围访问。

## 3. 架构决策

### AD-1：保留原生 LocalSend 协议

常规应用间传输继续使用 `serverProvider`、`sendProvider`、`ReceiveController` 和现有 `/api/localsend/v1|v2` 路由。前几个阶段的 UI 工作不得重写此传输层。

备份支持以增量方式添加，但控制面和文件传输面必须分开：计划、提交查询、回执恢复和取消使用独立的 `/api/localshare/backup/v1/...` 协议；接收批准、上传令牌和文件字节仍使用现有 LocalSend v2 `prepare-upload/upload`。备份元数据只作为顶层 `localShareBackup` 命名空间附加到普通 `prepare-upload` 请求，不修改 LocalSend DTO、路由或协议版本。

### AD-2：网页网关与原生服务器并行运行

创建独立的 `WebGatewayService` 和监听器。仅当至少存在一个网页会话时启动，并在最后一个会话过期或关闭时停止。

- 原生监听器：使用现有配置端口和 HTTP/HTTPS 设置，仅由 `serverProvider` 持有。
- 网页监听器：在独立的局域网端口上使用 HTTP，仅由 `webGatewayProvider` 持有。
- 端口选择：先尝试 `nativePort + 1`，然后尝试一个较小的确定性端口范围，最后使用操作系统分配的端口。在 `WebShareHandle` 中返回实际绑定的端口。
- 开始或结束网页共享时，绝不调用 `restartServer`。

这种分离可以避免浏览器兼容性选择改变原生协议、证书、组播状态或正在进行的原生接收任务。

### AD-3：传输清单与通道无关

文件选择、Android 备份扫描和浏览器上传会生成同一种领域级清单。原生适配器和网页适配器均使用该清单。平台句柄（`File`、`content://`、内存字节）不会出现在序列化 DTO 或备份台账中。

### AD-4：备份模块负责策略；传输模块只负责移动字节

备份引擎决定哪些媒体是候选项，维护每个目标的状态，创建运行任务，并提交确认结果。它不直接调用 UI 页面，也不会仅因下载已经开始就将文件标记为已备份。

### AD-5：网页传输是一项显式操作，而不是发送模式枚举值

保留 `SendMode.single` 和 `SendMode.multiple` 的原生行为。将隐藏的 `SendMode.link` 副作用替换为可见操作，例如**共享到浏览器**和**从浏览器接收**。迁移期间应安全反序列化旧的 `link` 值，但不得再次持久化该值。

### AD-6：浏览器限制是产品约定的一部分

可靠的零安装路径是普通浏览器下载（单个文件或生成的归档）。Chromium 的 File System Access API 不作为基线功能，因为通过手机普通局域网 HTTP 源提供的页面不属于安全上下文，无法在用户无感知的情况下写入任意目录。因此，只有 Windows LocalShare 客户端接收的原生备份可以自动核验；网页备份必须由用户在 Android 上人工确认，浏览器下载完成事件不能代替 Windows 持久回执。

## 4. 目标组件布局

```text
                           表现层
      +----------------------+-----------------------+
      |    原生传输 UI       | 网页 UI | 备份 UI     |
      +-----------+----------+----+---+------+--------+
                  |               |          |
                  v               v          v
          NativeTransferFacade  WebGateway  BackupCoordinator
                  |               |          |
                  |               |      +---+------------------+
                  |               |      | 扫描 + 计划 + 台账   |
                  |               |      +---+------------------+
                  |               |          |
                  +---------------+----------+
                                  |
                         TransferManifest
                                  |
                  +---------------+----------------+
                  |                                |
          LocalSend 原生传输                   局域网页传输
          现有 HTTPS/API 路由                  临时 HTTP 端口
```

依赖方向是经过明确设计的：

- 页面依赖视图模型/provider。
- Provider 依赖传输/备份服务。
- 传输服务依赖 DTO 和字节源。
- 备份数据库和 MediaStore 代码绝不导入 Flutter widget 或 Routerino。
- 现有原生路由控制器绝不导入网页网关状态。

## 5. 领域模型和服务契约

在 `app/lib/model/transfer/` 下添加以下非生成源文件：

```dart
enum TransferPurpose { adHoc, backup }
enum TransferChannel { nativePeer, webGateway }

class TransferItemDescriptor {
  final String id;                 // UUID generated once per manifest/run
  final String displayName;
  final String relativePath;       // normalized `/`, never absolute
  final int size;
  final String mime;
  final DateTime? modifiedAtUtc;
  final DateTime? capturedAtUtc;
  final String? contentSignature;  // e.g. size:mtime, optional strong hash
}

class TransferManifest {
  final String id;
  final TransferPurpose purpose;
  final List<TransferItemDescriptor> items;
  final int totalBytes;
  final DateTime createdAtUtc;
}

abstract interface class TransferSource {
  TransferItemDescriptor get descriptor;
  bool get supportsRandomAccess;
  Stream<List<int>> openRead({int start = 0, int? endExclusive});
}

class TransferPayload {
  final TransferManifest manifest;
  final Map<String, TransferSource> sources; // keyed by item id
}
```

具体数据源放在 `app/lib/transfer/source/` 下：

- `FileTransferSource`：用于桌面端路径；
- `ContentUriTransferSource`：用于 Android SAF/MediaStore URI；
- `MemoryTransferSource`：用于文本/剪贴板字节；
- 后续添加 `ZipTransferSource`：用于流式备用归档。

`TransferSource` 有意设计为不可序列化。只有 `TransferItemDescriptor` 会跨越网络或数据库边界。添加 `CrossFileTransferAdapter`，使现有选择器继续可用，而无需将 `CrossFile` 扩展成长生命周期的架构模型。

### 原生外观层

添加 `app/lib/transfer/native/native_transfer_facade.dart`：

```dart
abstract interface class NativeTransferFacade {
  Future<NativeTransferHandle> send({
    required Device target,
    required TransferPayload payload,
    required bool background,
  });
}
```

初始实现将描述符转换回 `CrossFile`/`SendingFile` 后，委托给 `sendProvider.startSession`。后续再将纯传输代码移出 `SendNotifier`，但保留 `sendProvider` 作为面向 UI 的状态适配器，使原生行为和页面不必一次性全部变更。

### 网页网关外观层

添加 `app/lib/provider/network/web_gateway/web_gateway_provider.dart`，并提供以下公开接口：

```dart
Future<WebShareHandle> createDownloadSession({
  required TransferPayload payload,
  required WebApprovalPolicy approval,
  Duration ttl = const Duration(minutes: 15),
});

Future<WebShareHandle> createUploadSession({
  required WebUploadDestination destination,
  required WebApprovalPolicy approval,
  WebUploadLimits limits = const WebUploadLimits.defaults(),
  Duration ttl = const Duration(minutes: 15),
});

void approveClient(String requestId);
void rejectClient(String requestId);
Future<void> closeSession(String sessionId);
```

建议在 `app/lib/model/state/web_gateway/` 下添加以下模型：

- `WebGatewayState`：监听器状态、绑定的地址/端口、活动会话和最后一个错误；
- `WebGatewaySession`：方向、用途、清单/目标、生命周期、过期时间、能力令牌摘要、客户端请求和进度；
- `WebClientRequest`：随机请求 ID、IP、解析后的 `User-Agent`（用户代理）、创建时间，以及 pending/approved/rejected 状态；
- `WebClientLease`：随机 Bearer 令牌摘要、客户端请求 ID、过期时间和 revoked 标志；
- `WebShareHandle`：会话 ID、显示 URL、二维码负载、原始能力令牌（capability token）和过期时间。原始能力令牌会返回给创建者 UI，但不记录日志，也不持久化。

不要将客户端 IP 用作 `sessionId`、请求 ID 或 Bearer 令牌。IP 只能作为显示/审计信息以及软限流键记录。

## 6. 网页网关协议

使用新的版本化命名空间。不要向 `ApiRoute` 添加浏览器行为，也不要更改 LocalSend v2 响应结构。

建议链接：

```text
http://192.168.1.20:53318/#/session/<sessionId>?key=<256-bit-base64url-capability>
```

URL 片段（fragment）不会随初始 HTTP 请求发送。网页应用读取它，并将其换取短期客户端访问租约（lease）。避免将密钥放入普通查询字符串、访问日志或来源信息（referrer）中。

建议端点：

| 方法和路由 | 用途 |
| --- | --- |
| `GET /` 和 `GET /assets/...` | 提供响应式单页客户端。HTML 中不嵌入会话数据。 |
| `POST /api/localshare/web/v1/access-requests` | 提交 `sessionId`、能力令牌（capability token）、可选 PIN 和客户端标签。返回随机请求 ID 以及 `pending`/`approved`。 |
| `GET /api/localshare/web/v1/access-requests/{requestId}` | 轮询批准状态。批准后，设置一个短期、仅作用于当前主机、`HttpOnly`、`SameSite=Strict` 的访问租约 cookie（lease cookie），将作用域限制到 API，并返回会话元数据。 |
| `GET /api/localshare/web/v1/sessions/{sessionId}` | 为已授权客户端返回方向、清单摘要、限制和能力。 |
| `GET`、`HEAD /api/localshare/web/v1/sessions/{sessionId}/files/{fileId}` | 下载元数据或字节。支持 `Range`、`If-Range`、`ETag`、`206` 和 `416`。 |
| `POST /api/localshare/web/v1/sessions/{sessionId}/uploads` | 提交经过清理的上传清单，并创建上传事务。 |
| `HEAD /api/localshare/web/v1/uploads/{uploadId}/files/{fileId}` | 返回可用于恢复传输的持久化字节偏移量。 |
| `PUT /api/localshare/web/v1/uploads/{uploadId}/files/{fileId}` | 使用 `Content-Range` 流式传输字节；写入临时 `.part` 文件。 |
| `POST /api/localshare/web/v1/uploads/{uploadId}/complete` | 校验大小/哈希，原子化完成文件，然后报告已提交的项目 ID。 |
| `DELETE /api/localshare/web/v1/uploads/{uploadId}` | 取消并删除临时数据。 |

所有 API 路由均为同源。不要启用宽松的 CORS。每个会话端点都需要访问租约 cookie（lease cookie）；更改状态的请求还需要完全匹配的 `Origin` 和会话 CSRF nonce。此处 cookie 优于 `Authorization` 请求头，因为普通 `<a>` 下载可以直接将数 GB 文件流式传输到浏览器下载管理器，无需在 JavaScript 中缓冲。网关仅存储访问租约摘要。由于该端点使用普通局域网 HTTP，因此无法将 cookie 标记为 `Secure`；较短的 TTL 以及文档中说明的恶意局域网限制仍然十分重要。使用恒定时间摘要比较、有限的请求体大小、按 IP 和会话限流、会话过期机制，并在主机关闭页面时撤销访问租约。

### HTTP/路由器工作

添加上传路由前，替换或扩展 `app/lib/util/simple_server.dart`。所需能力包括：

- 表示 GET、HEAD、POST、PUT、DELETE 和 OPTIONS 方法；
- 路径参数或小型路由匹配器；
- 用于授权、请求大小限制、本地接口过滤、脱敏日志以及异常到 JSON 映射的中间件；
- 无需 `rootBundle.loadString` 的流式二进制/静态响应；
- 浏览器断开连接时传播取消操作；
- 正确的响应关闭与刷新（flush）行为。

初期应将此路由器保持为新网关的私有实现。在同一次变更中将 LocalSend 原生控制器迁移到该路由器，会不必要地增加兼容性风险。

### 下载细节

- 对相对路径执行一次规范化并保留在清单中；绝不在领域模型中扁平化目录。
- 对于单个文件，设置兼容 RFC 6266 的 `filename` 和 `filename*` 参数。
- `ETag` 必须在会话生命周期内保持稳定，并包含项目身份、大小和修改签名。
- 桌面文件可以使用 `File.openRead(start, end)` 处理范围请求。
- 当前 `uri_content` 流从第 0 字节开始。在 Android 实现支持随机访问（seek）前，对 `content://` 数据源公布 `Accept-Ranges: none`；不要通过在 Dart 中丢弃数 GB 数据来伪造续传。
- 多文件浏览器备用方案可以流式生成 ZIP64，但不得在内存中缓冲归档或所有文件内容。已经压缩的媒体应使用 ZIP `STORE`。

### 上传细节

- `webkitdirectory` 可以在 Chromium 中提供相对路径；所有浏览器仍保留普通多文件输入。
- 拒绝绝对路径、`..`、NUL、设备名、驱动器前缀、备用数据流语法，以及规范化后变为空的路径组件。
- 接受清单前应用 Windows 安全的冲突处理策略。绝不静默覆盖现有文件。
- 将每次上传写入对应事务的暂存目录。只有在预期长度（以及提供哈希时的哈希）校验通过后，文件才可见。
- 浏览器进度以网关确认的字节数为准，而不是 JavaScript 仅仅读取的字节数。

## 7. Android 手动备份引擎

### 扫描源

交互式 `AssetPicker` 不作为备份清单。添加专用的分页 MediaStore 桥接层：

- `app/android/app/src/main/kotlin/org/localsend/localsend_app/MediaStoreChannel.kt`
- 从 `MainActivity.configureFlutterEngine` 或小型插件类注册 MethodChannel（方法通道）；
- Dart 适配器位于 `app/lib/backup/media/android_media_catalog.dart`。

查询所选集合中的图片和视频（初始默认值：`DCIM/Camera`，可选 `Pictures` 和已命名相册）。返回分页结果，而不是构建一个巨大的 MethodChannel（方法通道）结果。

最少包含以下行字段：

```text
volumeName, mediaStoreId, contentUri, displayName, relativePath,
mime, size, dateModifiedSeconds, dateTakenMillis, generationModified?
```

使用 `volumeName:mediaStoreId` 作为平台键，并使用 `(size, modified time, relative path)` 作为变更签名。只使用 ID 并不充分，因为 MediaStore 行可能消失或被复用。强哈希为可选项，仅在变更不明确或需要验证时延迟计算。

只请求图片/视频读取权限。Android 13 需要 `READ_MEDIA_IMAGES` 和 `READ_MEDIA_VIDEO`；更早的受支持 Android 版本使用带合适 `maxSdkVersion` 的 `READ_EXTERNAL_STORAGE`。在 Android 14 及以上版本中，检测所选照片访问权限，并在应用无法查看完整媒体库时告知用户。仅复制原始字节时不需要 `ACCESS_MEDIA_LOCATION`，除非位置元数据行为要求该权限。

### 台账

添加真正的 SQLite 数据库；不要将备份记录追加到 SharedPreferences。适合使用基于 Drift 的实现，因为需要数据库迁移和类型化查询。建议源目录：`app/lib/backup/database/`。

逻辑架构：

| 表 | 关键字段 | 用途 |
| --- | --- | --- |
| `backup_targets` | `target_id`、类型、原生指纹、显示名称、创建时间/最近成功时间 | 已命名的 Windows 客户端或手动命名的浏览器目标。 |
| `backup_sources` | `source_id`、`target_id`、存储卷、相对路径/相册选择器、是否启用 | 目标包含的集合。 |
| `backup_media` | 平台键、内容 URI、路径、名称、MIME、大小、修改时间/拍摄时间、签名 | 最新的 Android 清单快照。 |
| `backup_item_state` | `(target_id, platform_key)`、已确认的签名/路径/时间 | 确定已提交到该目标的最后一个版本。 |
| `backup_runs` | 运行 ID、目标 ID、通道、状态、总计、时间戳 | 持久化的手动运行日志。 |
| `backup_run_items` | `(run_id, platform_key)`、计划路径、签名、状态、字节数、错误 | 恢复/重试和项目级确认。 |

运行状态应当单调递进：`draft -> scanning -> ready -> transferring -> awaitingConfirmation -> committed`，并包括 `failed` 和 `canceled` 终止分支。项目状态应区分 `planned`、`transferring`、`transferred`、`confirmed` 和 `failed`。

只有 `confirmed` 项目才更新 `backup_item_state`：

- 原生目标：Windows 报告最终文件已经持久化，且运行提交响应中列出了该项目 ID。
- 浏览器目标：传输完成后仍保持 `awaitingConfirmation`；用户在保存/解压下载内容后，在 Android 上明确确认。浏览器 `download` 事件不能证明文件已持久化到磁盘。

初始产品绝不将手机上的删除操作传播到 Windows。

### 协调器

添加 `app/lib/backup/backup_coordinator.dart` 和 `app/lib/provider/backup_provider.dart`，提供不依赖 UI 的 API：

```dart
Future<BackupScanSummary> scan(String targetId);
Future<BackupRun> createRun(String targetId, Iterable<String> mediaKeys);
Future<void> startNativeRun(String runId, Device windowsTarget);
Future<WebShareHandle> startBrowserRun(String runId);
Future<void> confirmBrowserRun(String runId, Set<String> itemIds);
Future<void> retryFailed(String runId);
Future<void> cancel(String runId);
```

扫描、数据库写入、清单创建和传输执行必须能够独立测试。协调器发出状态；页面负责渲染状态。

## 8. 完整原生备份传输

常规临时原生传输保持不变。当前实现把备份回执协议作为现有原生监听器上的控制面扩展，文件批准和字节流则完整复用 LocalSend v2：

| 层 | 方法和路由 | 当前用途 |
| --- | --- | --- |
| LocalShare 回执控制面 | `POST /api/localshare/backup/v1/plan` | Android 提交当前清单、清单 SHA-256、目标指纹以及 `fileId -> mediaKey` 映射；Windows 恢复可核验的中断状态，并返回 `requiredMediaKeys` 和已经持久化的 `committedItems`。Android 在上传前先严格核验该响应。 |
| LocalSend 文件传输面 | `POST /api/localsend/v2/prepare-upload` | 使用普通 LocalSend 请求批准和令牌分配流程。请求仍包含标准 `info/files`，另附顶层 `localShareBackup`；Windows 校验来源/目标指纹、清单摘要、文件映射、相对路径、文件名和大小。备份扩展不支持 v1。 |
| LocalSend 文件传输面 | `POST /api/localsend/v2/upload?sessionId=...&fileId=...&token=...` | 使用普通 LocalSend 会话和上传 isolate 发送文件字节；`fileIdToMediaKey` 将临时文件 ID 绑定到稳定的媒体键。 |
| LocalShare 回执控制面 | `POST /api/localshare/backup/v1/commit` | 上传结束后查询与当前清单逐项匹配的 Windows 持久回执并返回 `committedItems`。文件的原子提交已经在 `upload` 处理期间完成；此路由不再次移动文件。Android 只自动确认响应中通过严格校验的项目。 |
| LocalShare 回执控制面 | `POST /api/localshare/backup/v1/receipt` | 断线、应用重启或最终响应丢失后，按当前清单显式查询持久回执，恢复“电脑已落盘但手机尚未记账”的项目。 |
| LocalShare 回执控制面 | `POST /api/localshare/backup/v1/cancel` | 清除匹配批次的活动备份控制关联并返回取消时间；不删除已经核验的持久回执。正在运行的 LocalSend 传输仍由普通 LocalSend `cancel` 路由取消。 |

不存在 `/api/localshare/backup/v1/prepare` 或 `/api/localshare/backup/v1/upload`。协议模型、严格 JSON 编解码和路由常量位于 `app/lib/features/backup/protocol/`，四个控制面路由由 `BackupController` 注册；普通 `prepare-upload/upload` 的备份接入由 `ReceiveController` 处理。`localShareBackup.protocolVersion` 独立于 LocalSend `protocolVersion`，当前通过调用 `plan` 探测能力：返回 `404/405` 表示目标不支持自动备份回执，因此不会继续向未修改的 LocalSend 对等端发送带扩展的上传请求。

一次原生备份按以下顺序执行：

1. Android 调用 `plan`，恢复已有回执并取得仍需上传的媒体键。
2. Android 只为缺失子集构造普通 LocalSend v2 `prepare-upload` 请求，并在 `localShareBackup` 中携带当前子集清单、清单摘要、目标指纹和一一对应的文件映射。
3. Windows 按普通 LocalSend 流程批准或快速保存并签发上传令牌；Android 使用普通 `upload` 路由并发发送字节。
4. Windows 将每个文件写入最终目录同卷的确定性 `.part` 文件，完成 `flush/close`，核对实际字节数并计算 SHA-256；若清单提供预期哈希则同时比对。随后先持久化待提交签名、再次检查目标冲突、原子重命名，最后将项目标记为已核验。
5. Android 调用 `commit`，验证响应中的协议版本、批次、来源、目标、清单摘要和每个项目签名，只把可信的 `committedItems` 自动写入手机台账。未返回或失败的项目继续留在待处理清单中。
6. 如果第 4 步已经完成但第 5 步响应丢失，下一次 `plan` 或显式 `receipt` 从 Windows 的 SQLite 回执账本恢复结果，不需要重新传输文件。

同一个 `batchId` 在部分项目确认后可以继续用于更小的待处理子集，此时 `itemCount`、`totalBytes` 和 `manifestSha256` 会变化。Windows 不能仅凭批次总数或总字节数拒绝重试；批次层绑定来源设备、目标配置、批次 ID、目标指纹、协议架构和创建时间，项目层则按 `mediaKey` 及完整媒体元数据（包括可选预期 SHA-256）逐项检查冲突和回执匹配。

Windows 的接收目录是“备份收件箱”，不是由 LocalShare 长期托管的媒体库。只有完成临时写入、大小/哈希核验、原子重命名并持久化回执的项目才能出现在 `plan`、`commit` 或 `receipt` 的 `committedItems` 中。Android 客户端以 Windows 回执自动确认，不再要求用户在手机上点击“备份成功”。

回执一旦提交，后续不再因为收件箱中的原文件缺失而撤销。用户会在备份后把照片和视频移动到自己的归档目录；如果持续扫描原接收路径，会把正常移动误判为丢失并造成全量重传。实际路径检查只用于本次提交和处于 `writing`/`ready` 状态的崩溃恢复。以后若增加“托管备份库完整性检查”，必须作为独立可选模式，不能改变默认收件箱语义。

上述自动核验只适用于 Android LocalShare 客户端到 Windows LocalShare 客户端。网页备份仍保持人工确认：手机只能知道响应字节已经交给浏览器，无法证明浏览器最终写入了磁盘，也无法读取实际保存路径。不得用网页下载完成、链接打开或 HTTP 响应结束自动推进备份台账。

当前实现的一次控制请求携带当前待处理清单；固定大小的描述符分页（例如每页 500-1000 项）仍属于大型媒体库加固项，不能在实现前宣称已经支持。文件上传已经复用现有工作 isolate 并发机制，备份调用传入独立文件列表，不得清除用户临时传输选择。

## 9. UI 和导航集成

现代 UI 是这些服务之上的表现层；传输状态不得存储在 widget 中。

建议的主要目标页面：

- **接收**：原生可用状态、待处理原生请求，以及可见的**从浏览器接收**操作。
- **发送**：文件/媒体/文件夹选择、附近原生设备，以及可见的**共享到浏览器**操作。
- **备份**：Android 目标卡片和手动扫描/运行流程；Windows 目标/根目录管理和传入备份历史。
- **设置**：网络、安全、外观和存储。

当前四个标签在 Android 和 Windows 上都保持相同顺序。不要在继续使用 `HomeTab.values` 索引的同时有条件地插入 widget；`PageView`、`NavigationRail` 和 `NavigationBar` 必须共同使用同一份标签列表，避免平台差异移动“设置”位置或破坏 `jumpToPage(tab.index)`。

具体表现层新增内容：

- `app/lib/pages/web_transfer/web_share_page.dart`
- `app/lib/pages/web_transfer/web_receive_page.dart`
- `app/lib/pages/backup/backup_page.dart`
- `app/lib/pages/backup/backup_target_page.dart`
- `app/lib/pages/backup/backup_run_page.dart`
- 相应的视图模型文件/provider；不得从 widget 直接调用网络或 SQL。

迁移期间，`app/lib/pages/web_send_page.dart` 可以临时包装新的共享页面，以保持路由兼容；所有调用方迁移后即可删除。新页面订阅 `webGatewayProvider`；它不得在 `initState`/`PopScope` 中持有服务器启动/停止逻辑。

## 10. 具体文件集成计划

### 需要有计划地修改的现有文件

| 文件 | 变更 |
| --- | --- |
| `app/lib/pages/home_page.dart` | 从一份稳定的描述符列表渲染目标页面；添加“备份”，不依赖枚举位置。 |
| `app/lib/pages/home_page_controller.dart` | 按稳定标签 ID 导航，而不是枚举序号。 |
| `app/lib/pages/tabs/send_tab.dart` / `send_tab_vm.dart` | 分别公开原生发送和网页共享操作；不再将链接共享视为 `SendMode`。 |
| `app/lib/pages/tabs/receive_tab.dart` / `receive_tab_vm.dart` | 公开浏览器上传会话创建和传入网页请求。 |
| `app/lib/pages/web_send_page.dart` | 迁移期间的兼容包装器；不重启服务器。 |
| `app/lib/config/init.dart` | 初始化备份数据库并注入 override；原生服务器启动保持不变。 |
| `app/lib/provider/network/server/server_provider.dart` | 在现有原生监听器注册独立的 `BackupController`，同时保持普通 LocalSend 路由和会话生命周期不变。 |
| `app/lib/provider/network/server/controller/send_controller.dart` | 在新网关稳定前冻结为旧版 WebSend 兼容实现，然后移除其静态/浏览器路由。 |
| `app/lib/provider/network/server/controller/receive_controller.dart` | 在普通 v2 `prepare-upload` 中解析并校验 `localShareBackup`，把普通 `upload` 文件写入流程连接到暂存、核验和持久回执；无扩展字段时保持常规 LocalSend 行为。 |
| `app/lib/provider/network/send_provider.dart` | `startBackupSession` 编排 `plan -> 普通 prepare/upload -> commit`，复用既有上传 isolate，并且只返回经过 Windows 回执校验的媒体键。 |
| `app/lib/util/simple_server.dart` | 初期不要执行风险较高的原地原生重写；在其旁边提取/引入功能更丰富的网关路由器。 |
| `app/lib/model/cross_file.dart` | 保留为选择器兼容模型；避免添加备份台账字段。 |
| `app/lib/provider/persistence_provider.dart` | 仅持久化小型备份偏好/功能标志；数据库行存放在其他位置。 |
| `app/pubspec.yaml` | 显式添加所选 SQLite/Drift 和网页资源构建依赖；不要依赖传递依赖 `photo_manager`。 |
| `app/android/app/src/main/AndroidManifest.xml` | 修正按版本区分的媒体权限和 Android 14 行为。 |
| `app/android/app/src/main/kotlin/org/localsend/localsend_app/MainActivity.kt` | 注册专用 MediaStore MethodChannel（方法通道）/插件；保持现有选择器方法不变。 |
| `common/lib/api_route_builder.dart` | 保持 LocalSend 路由稳定。 |

### 新实现区域

```text
app/lib/model/transfer/
app/lib/model/state/web_gateway/
app/lib/transfer/source/
app/lib/transfer/native/
app/lib/provider/network/web_gateway/
app/lib/provider/network/web_gateway/controller/
app/lib/pages/web_transfer/
app/lib/backup/
app/lib/backup/database/
app/lib/backup/media/
app/lib/pages/backup/
app/assets/web/localshare/
app/lib/features/backup/protocol/
app/lib/features/backup/receiver/
app/lib/provider/network/server/controller/backup_controller.dart
```

生成的 `*.mapper.dart`、Drift 输出、Flutter 资源和 slang 输出必须通过仓库的构建流程重新生成；绝不手动编辑生成文件。

## 11. 生命周期、并发和资源规则

- 原生会话和网页会话可以共存，因为它们使用不同的监听器和状态持有者。
- 首个网页网关版本可以在允许多个只读下载客户端的同时，仅允许一个写入字节的上传事务处于活动状态。应将其编码为明确策略并返回 `409`，而不是依赖偶然的全局状态。
- 关闭 UI 路由不会自动销毁传输任务。Provider 持有会话；由用户选择停止或保持运行。
- Android 活动传输需要前台服务通知，以确保熄屏/后台时的可靠性。只与 `ProgressPage` 绑定的周期性唤醒锁（wake lock）不足以支撑由 provider 持有的网页/备份传输。
- 每个流订阅、临时文件、定时器、访问租约（lease）和监听器都有唯一持有者以及确定性的释放路径。
- 启动恢复区分无内容签名的 `writing` 和已持久化签名的 `ready`：前者不能自动核验；后者只有在最终文件大小和 SHA-256 再次匹配时才转为 `verified`。
- 必须分别测试原生端口和网页端口的 Windows 防火墙行为。将网关绑定到局域网接口，以及在文档中说明“专用网络”权限，都是发布要求。
- IPv6 URL 使用方括号格式；IPv4 和 IPv6 均可用时，二维码优先使用可用的 IPv4 地址。

## 12. 安全不变量

1. 网页会话默认关闭、有时限，并由主机显式创建。
2. 通过随机 256 位能力令牌（capability token）加上主机批准的客户端访问租约（lease）授权访问；IP 和 `User-Agent`（用户代理）都不是身份标识。
3. 存储能力令牌/访问租约摘要，而不是可重复使用的明文密钥。从日志中隐藏 URL 片段、PIN、令牌和 `Authorization` 请求头。
4. PIN 是可选的第二因素。在内存中对其进行哈希并限制尝试频率；不要将其放入二维码查询参数。
5. 仅接受可通过本机局域网接口到达的客户端，并遵循配置的网络允许/拒绝策略。UI 必须提供公共/访客 Wi-Fi 警告。
6. 防止路径遍历、符号链接逃逸、Windows 保留名称、覆盖竞态、解压缩炸弹，以及不受限制的文件数量和大小。
7. 浏览器 HTTP 无法防止恶意局域网监听者窃听。必须明确说明这一点。仍应推荐使用加密的原生 LocalShare 传输路径。
8. 使用 Windows 客户端时，备份目标身份是原生证书指纹。浏览器目标配置文件只是手动命名的记录标识，而不是加密设备身份。

## 13. 分阶段实现

### 阶段 0——保护基线

- 将分支固定到 v1.17.0，并记录具有代表性的 Windows ↔ Android 原生传输测试。
- 添加覆盖路由兼容性、目录名、接受、取消和 `content://` URI 发送的测试。
- 独立引入视觉外壳，不移动传输代码。

退出标准：现有原生传输和设备发现行为与之前完全一致。

### 阶段 1——与通道无关的负载和独立网关

- 添加传输描述符/数据源和 `CrossFileTransferAdapter`。
- 添加 `webGatewayProvider`、监听器生命周期、能力令牌/访问租约状态、功能更丰富的私有路由器和新网页资源。
- 实现应用 -> 浏览器单文件/多文件下载和标准文件 Range。
- 将可见的**共享到浏览器**操作连接到新网关；在实现完全对等前，将旧版 WebSend 保留为开发备用方案。

退出标准：开始网页共享不会重启或更改原生服务器，原生传输仍可并发工作。

### 阶段 2——浏览器 -> 应用

- 添加上传清单、主机批准、暂存、续传偏移量、路径验证、进度、提交和清理。
- 在“接收”中添加**从浏览器接收**，并使用 Edge/Chrome 和一个基本非 Chromium 浏览器测试 Windows/Android 主机。

退出标准：零安装发送端可以上传文件，受支持的 Chromium 可以上传文件夹，同时不会削弱原生 API 的安全性。

### 阶段 3——备份清单和台账

- 添加 MediaStore 分页/权限、目标/来源设置、SQLite 架构/迁移、扫描差异、运行日志和备份 UI。
- 使用既有的应用 -> 浏览器网关创建浏览器备份运行任务。
- 提交浏览器运行任务前，要求用户在 Android 上明确确认。

退出标准：重复扫描只显示每个已命名目标对应的新增/变更项目，包括应用重启或运行中断后的情况。

### 阶段 4——完整 Windows 客户端备份

- 添加 LocalShare `plan/commit/receipt/cancel` 回执控制面；不要在该命名空间重复实现 `prepare/upload`。
- 在普通 LocalSend v2 `prepare-upload` 请求的 `localShareBackup` 命名空间中附加清单、摘要、目标指纹和文件映射，并继续复用普通 `upload` 工作 isolate。
- 添加 Windows 备份收件箱、SQLite 回执账本、同卷暂存、大小/SHA-256 核验、原子重命名和中断恢复；只有在协议测试存在后才添加可续传分块。

退出标准：Windows 对本次写入完成自动核验并持久化回执，Android 只自动确认 Windows 返回且通过当前清单签名校验的项目；用户以后移动收件箱文件不会撤销既有回执。

### 阶段 5——加固并移除旧实现

- 添加大型媒体库、>4 GiB、磁盘空间不足、熄屏、断开/重连、Unicode、冲突和恶意路径测试。
- 如果 UX 仍然需要，添加流式 ZIP64 备用方案。
- 只有在新网页流程成功发布且不再有内部调用方后，才移除旧版 WebSend 路由/状态/资源。
- 审查此分支的许可证声明、应用 ID、名称、图标、更新端点和 LocalSend 兼容性声明。

## 14. 迁移注意事项

- **不要将 UI 重写与原生传输提取混在一起。** 在表现层和网页功能演进期间，保留一条已知可靠的原生路径。
- **不要为新网关复用 `ServerState.webSendState`。** 这会重新引入本设计要消除的单例耦合。
- **不要随意更改现有 `/api/localsend/v2` JSON 或 `protocolVersion`。** 必须继续与较旧的 LocalSend 对等端互操作。
- **不要将原始 `CrossFile`、`AssetEntity`、路径、流控制器或 content URI 持久化为备份证明。** 媒体权限和 URI 可能变化；应从当前清单重新构建活动数据源。
- **不要将大型媒体台账放入 Windows 设置 JSON 或 SharedPreferences。** 使用经过迁移测试的数据库。
- **在数据源能够随机访问（seek）前，不要声称支持续传。** 桌面 `File` 和 Android ContentProvider（内容提供器）的能力不同。
- **不要根据 HTTP 响应或 JavaScript 下载点击推断浏览器备份成功。** 除非由 Windows 客户端提交，否则必须要求明确确认。
- **不要依赖 Android 应用的前台状态。** 长时间手动传输仍需要前台服务生命周期支持。
- **不要信任浏览器提供的文件元数据或相对路径。** 在接收端验证，并在读取请求体前强制执行数量/大小配额。
- **没有策略检查时，不要暴露所有接口。** 在不受信任的网络中，仅使用 `0.0.0.0` 加二维码密钥并不充分。
- **不要手动编辑生成的 mapper/翻译。** 添加模型后需要 build-runner 输出和架构迁移测试。
- **不要将仅浏览器支持的 API 作为基线承诺。** 文件夹选择和直接写入目录的能力会随浏览器及安全上下文规则而变化。

## 15. 最低验证矩阵

| 流程 | 必需检查项 |
| --- | --- |
| Windows 应用 -> Android 应用 | 发现、PIN、接受/拒绝、文件/文件夹、取消、重试、Unicode |
| Android 应用 -> Windows 应用 | MediaStore/content URI、熄屏、>4 GiB 视频、修改时间 |
| 应用 -> 浏览器 | 原生传输并发、批准、过期、访问租约撤销、Range/ETag、断开连接 |
| 浏览器 -> 应用 | 多文件、Chromium 文件夹、冲突/路径攻击、配额、续传、磁盘空间不足 |
| 浏览器备份 | 首次/第二次扫描、中断批次、不产生错误提交、人工全部/部分确认、下载完成事件不得自动确认 |
| 原生备份 | 目标/来源指纹核对、普通 LocalSend v2 批准与上传、大小/哈希/原子提交、暂存恢复、回执丢失恢复、部分失败重试、客户端自动确认可信项目、文件移走后不重复备份 |
| 网络/安全 | Windows 防火墙专用/公用配置文件、访客 Wi-Fi 警告、IP 变更、IPv4/IPv6、限流 |

核心验收标准是相互分离：常规原生传输、临时网页会话和备份策略中的任何一项都可以独立演进或失败，而不会在不知情的情况下改变另外两项的状态或保证。
