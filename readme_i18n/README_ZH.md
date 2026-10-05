# LocalShare

[English](../README.md) | [简体中文](README_ZH.md)

LocalShare 是一个面向 Windows 和 Android 的局域网文件互传与手机媒体备份工具。

项目基于 LocalSend 的局域网传输能力重新设计，重点解决日常文件互传、浏览器传输和手机照片视频手动备份三个场景。

## 下载

Windows 安装程序、便携包和 Android APK 请从 [LocalShare GitHub 发行版](https://github.com/TeaDrink666/LocalShare/releases/latest) 下载。

## 功能

- Android 与 Windows 客户端之间通过局域网发送和接收文件。
- 传输统一显示为任务，包含进度、速度和时间估算；切换页面后任务继续执行。
- 默认同时运行 2 个传输任务，设置可调整为 1–8 个，其余排队；媒体同步最多同时运行 1 个。
- 原生 LocalShare 传输支持暂停和续传，保留任务记录；普通接收使用独立任务目录，保留原文件名和目录结构。
- 通过链接或二维码，让浏览器发送文件或接收文件，浏览器端不需要安装客户端。
- Android 手动扫描全部图片和视频，并增量备份到指定 Windows 电脑。
- 普通文件接收目录与手机备份目录分别设置，互不混用。
- 手机备份不保留原始相册目录层级，统一保存到备份目录下的“图片”和“视频”文件夹。
- Windows 端使用临时文件、大小校验、SHA-256 校验、原子改名和 SQLite 回执记录。
- 手机只根据 Windows 返回的已核验回执更新备份状态，不需要手动确认“备份成功”。
- 用户将已备份文件从 Windows 收件目录移动到自己的归档目录后，不会因此被重复备份。

## 备份语义

备份是手动触发的增量任务，不包含定时任务、后台自动备份、云中继或互联网传输。

Windows 收件目录是“备份收件箱”，不是由应用长期管理的媒体库。完成核验并写入回执后，文件可以由用户自行移动。网页备份仍需要人工确认，因为浏览器无法向 Windows 客户端证明文件最终写入了哪个目录。

详细架构和协议说明见 [`docs/LOCALSHARE_ARCHITECTURE.md`](../docs/LOCALSHARE_ARCHITECTURE.md)。
任务调度、续传兼容性和后台支持范围见 [`docs/TASK_CENTER.md`](../docs/TASK_CENTER.md)。

## 升级到 0.2.1

正式 Android APK 使用项目固定发布签名，可直接覆盖本地签名版 0.2.0。旧 GitHub 正式版 0.1.0 / 0.1.1 使用不同签名，需要先备份应用配置与记录，卸载旧版后安装 0.2.1。以后持续使用同一签名的版本可以覆盖升级。

Windows 沿用同一应用标识和自签名代码签名证书；安装程序支持升级，但系统仍可能显示发布者不受信任或 SmartScreen 提示。

完整更新内容见 [`CHANGELOG.md`](../CHANGELOG.md)。

## 本地构建

推荐环境：

- Flutter 3.24.5
- Dart 3.5.x
- JDK 17
- Android SDK 34、NDK 23.1.7779620
- Rust stable（`rhttp` 原生依赖使用）

首次准备依赖：

```powershell
cd app
flutter pub get
```

Android ARM64 Release APK：

```powershell
flutter build apk --release --target-platform android-arm64
```

正式 Android 安装包仅支持 `arm64-v8a`（ARM 64 位）。

仓库没有提交正式发布密钥时，构建会使用开发 keystore 生成可供测试安装的 Release 包；正式发布或上架应用商店前，需要配置自己的 `android/key.properties` 和 keystore。

Windows Release：

```powershell
flutter build windows --release
```

Windows Inno Setup 安装程序：

1. 先生成 Windows Release。
2. 使用 Inno Setup 编译 [`scripts/compile_localshare_setup.iss`](../scripts/compile_localshare_setup.iss)。

Windows 插件如果无法创建符号链接，请在管理员 PowerShell 中运行 [`scripts/compile_windows_debug_localshare.ps1`](../scripts/compile_windows_debug_localshare.ps1) 进行依赖准备。

## GitHub Actions

推送到 `main` 分支或手动运行 `LocalShare Build` 工作流后，GitHub Actions 会构建：

- Android `arm64-v8a` Release APK
- Windows x64 Release 便携包
- Windows x64 Inno Setup 安装程序

构建结果可以在对应 Actions 运行的 Artifacts 中下载。项目不把本地构建缓存、工具链或 `dist` 安装包提交到 Git 仓库。
未提供私有签名配置时，CI 构建使用开发签名；正式升级请使用 GitHub 发行版附带的已签名安装包。

## 测试

在 `app` 目录运行：

```powershell
flutter analyze
flutter test
```

## 许可证

本项目遵循仓库中的 [LICENSE](../LICENSE) 文件。项目基于 LocalSend 开源项目发展，相关原始版权和许可证信息保持在仓库历史与源文件中。
