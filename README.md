# LocalShare

LocalShare 是一个面向 Windows 和 Android 的局域网文件互传与手机媒体备份工具。

项目基于 LocalSend 的局域网传输能力重新设计，重点解决日常文件互传、浏览器传输和手机照片视频手动备份三个场景。

## 功能

- Android 与 Windows 客户端之间通过局域网发送和接收文件。
- 通过链接或二维码，让浏览器发送文件或接收文件，浏览器端不需要安装客户端。
- Android 手动扫描全部图片和视频，并增量备份到指定 Windows 电脑。
- Windows 端使用临时文件、大小校验、SHA-256 校验、原子改名和 SQLite 回执记录。
- 手机只根据 Windows 返回的已核验回执更新备份状态，不需要手动确认“备份成功”。
- 用户将已备份文件从 Windows 收件目录移动到自己的归档目录后，不会因此被重复备份。

## 备份语义

备份是手动触发的增量任务，不包含定时任务、后台自动备份、云中继或互联网传输。

Windows 收件目录是“备份收件箱”，不是由应用长期管理的媒体库。完成核验并写入回执后，文件可以由用户自行移动。网页备份仍需要人工确认，因为浏览器无法向 Windows 客户端证明文件最终写入了哪个目录。

详细架构和协议说明见 [`docs/LOCALSHARE_ARCHITECTURE.md`](docs/LOCALSHARE_ARCHITECTURE.md)。

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

Android Release 分架构 APK：

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64
```

只生成现代 Android 常用架构：

- `arm64-v8a`
- `x86_64`

仓库没有提交正式发布密钥时，构建会使用开发 keystore 生成可供测试安装的 Release 包；正式发布或上架应用商店前，需要配置自己的 `android/key.properties` 和 keystore。

Windows Release：

```powershell
flutter build windows --release
```

Windows Inno Setup 安装程序：

1. 先生成 Windows Release。
2. 使用 Inno Setup 编译 [`scripts/compile_localshare_setup.iss`](scripts/compile_localshare_setup.iss)。

Windows 插件如果无法创建符号链接，请在管理员 PowerShell 中运行 [`scripts/compile_windows_debug_localshare.ps1`](scripts/compile_windows_debug_localshare.ps1) 进行依赖准备。

## GitHub Actions

推送到 `main` 分支或手动运行 `LocalShare Build` 工作流后，GitHub Actions 会构建：

- Android `arm64-v8a` Release APK
- Android `x86_64` Release APK
- Windows x64 Release 便携包

构建结果可以在对应 Actions 运行的 Artifacts 中下载。项目不把本地构建缓存、工具链或 `dist` 安装包提交到 Git 仓库。

## 测试

在 `app` 目录运行：

```powershell
flutter analyze
flutter test
```

## 许可证

本项目遵循仓库中的 [LICENSE](LICENSE) 文件。项目基于 LocalSend 开源项目发展，相关原始版权和许可证信息保持在仓库历史与源文件中。
