# LocalShare 开发状态

更新日期：2026-07-13

## 当前工作区已实现功能

- 保留与 LocalSend 兼容的客户端发现和客户端互传功能。
- 主界面固定为“发送、接收、备份、设置”四个标签，启动后直接进入发送，不再设置内容繁杂的首页。
- 发送页统一选择内容，随后先显示附近设备，再显示“通过链接发送”；不再要求提前选择传送方式。
- 支持应用向浏览器提供下载，以及浏览器通过局域网上传到应用；均可使用局域网链接或二维码进入。
- 浏览器下载支持单文件 HTTP Range，以及真正流式输出的多文件 ZIP/ZIP64 压缩包。
- 浏览器上传支持文件选择、Chromium 文件夹选择、拖放、接收确认、PIN、进度显示和重试。
- Android 备份通过分页方式直接扫描 MediaStore 中的照片和视频，并支持多个存储卷。
- 每个命名的电脑档案拥有独立的已确认备份记录；只有用户明确确认后才会推进备份进度。
- 待确认批次可跨应用重启保留，且不会被新批次静默覆盖。
- 待确认批次可以重复发送；从链接页面返回或取消客户端等待后，不会锁死发送入口。
- Windows 默认接收目录使用系统下载目录的完整绝对路径，并在接收页直接显示实际保存位置。
- 浏览器 ZIP 压缩包中的 Windows 非法文件名和路径冲突会以确定性规则转换。

## 本机构建环境

项目使用以下专用构建工具目录：

- Flutter 3.24.5：`D:\software_D\LocalShare\flutter-3.24.5`
- Android SDK 34：`D:\software_D\LocalShare\android-sdk`
- Gradle 缓存和适合当前网络环境的仓库重定向：`D:\software_D\LocalShare\gradle-home`
- Kotlin 验证工具：`D:\software_D\LocalShare\kotlin-check`
- Visual Studio Build Tools 2022：`D:\software_D\Visual Studio\BuildTools`
- Windows 原生插件使用的 Rust/Cargo：`D:\software_D\Rust`

项目内的 `app/android/local.properties` 指向上述 Android SDK。使用
`scripts\compile_android_debug_localshare.ps1` 可按这些固定路径和 Gradle
缓存构建 Android Debug APK：

```powershell
cd D:\code\localshare
.\scripts\compile_android_debug_localshare.ps1
```

调用 Flutter 前，脚本会计算仓库内
`scripts\localshare_mirrors.init.gradle` 模板的哈希，并将其安全同步到专用的
`D:\software_D\LocalShare\gradle-home\init.gradle`。该模板会把 Google、
Maven Central、Gradle Plugin Portal 和旧版 JCenter 仓库重定向到阿里云镜像，
不会修改用户的全局 Gradle 主目录。

如果只想验证或刷新专用 init 脚本，而不构建 APK，可运行：

```powershell
.\scripts\compile_android_debug_localshare.ps1 -SyncGradleInitOnly
```

Debug APK 输出到
`app\build\app\outputs\flutter-apk\app-debug.apk`。第一次全新构建还会填充
Gradle、Cargo 和 Android 原生目标缓存，因此耗时明显长于后续构建。

### Windows Debug 构建（需要管理员权限）

Flutter 3.24.5 通常会为 `.flutter-plugins-dependencies` 中的每个条目，在
`app\windows\flutter\ephemeral\.plugin_symlinks` 下创建目录符号链接。
未以管理员权限运行且未开启开发者模式时，Windows 会阻止该操作。LocalShare
不会修改或开启开发者模式；仓库内的构建助手通过明确的 UAC 提权选项完成构建：

```powershell
cd D:\code\localshare
.\scripts\compile_windows_debug_localshare.ps1 -RunElevated
```

Windows 弹出常规 UAC 提示后，脚本会启动隐藏的管理员 PowerShell 工作进程。
父进程会等待构建完成，并报告退出码以及位于
`D:\software_D\LocalShare\windows-build-logs` 下带时间戳的完整日志路径。
如果当前终端已经以管理员身份运行，可以省略 `-RunElevated`。普通权限下不带该
参数运行时，脚本会在修改构建状态之前停止，并给出清晰说明。

构建助手固定使用 `D:\software_D\LocalShare\flutter-3.24.5` 中的 Flutter 和
`D:\software_D\Rust` 中的专用 Rust 环境，然后执行
`flutter build windows --debug --no-pub`。

生成的开发测试目录为 `app\build\windows\x64\runner\Debug`。运行时必须保留并
使用完整目录，不能只复制 `LocalShare.exe`。Debug 包依赖 Visual Studio
Build Tools 安装的 MSVC Debug 运行库，仅适合本机测试，不应直接分发给其他电脑。

Flutter 在 Windows 构建前会检查清单 `plugins.windows` 中的所有项目。
`dart:io Link.existsSync` 不会把 NTFS Directory Junction 识别为符号链接，因此
Junction 无法绕过 Flutter 对真实符号链接的要求。管理员构建开始前，助手会安全
移除受管目录中的诊断 Junction，再由 Flutter 创建真实目录符号链接。CMake 只会
使用其中属于原生/FFI 插件的子集。

如果只想诊断清单和文件系统，可在不启动 Visual Studio、CMake、Rust 或 Flutter
编译的情况下准备 Junction：

```powershell
.\scripts\compile_windows_debug_localshare.ps1 -PrepareJunctionsOnly
```

这些 Junction 仅用于诊断，不能替代管理员权限。管理员构建路径会先验证每个项目
都是工作区 `.plugin_symlinks` 目录的直接子项，再以非递归方式将其移除；不会遍历
任何插件目标目录。

插件依赖发生变化后，应先在管理员终端中运行 `flutter pub get`，重新生成
`.flutter-plugins-dependencies`，然后再次运行构建助手。

## 验证方式

在 `D:\code\localshare\app` 中运行：

```powershell
D:\software_D\LocalShare\flutter-3.24.5\bin\flutter.bat analyze --no-pub
D:\software_D\LocalShare\flutter-3.24.5\bin\flutter.bat test --no-pub
node --check assets\web\main.js
node --check assets\web\receive.js
```

当前测试套件包含 221 项通过的 Flutter 测试，覆盖增量规划、电脑档案持久化、
MediaStore 适配、HTTP Range 解析和路由、流式 ZIP/ZIP64 输出、Windows 安全路径
以及内嵌网页资源。

## 手动备份流程

1. 在 Android 端打开“手机媒体备份”。
2. 选择或创建目标电脑档案。
3. 选择照片、视频范围，并扫描变更。
4. 在扫描结果下直接选择附近电脑，或使用下方的局域网链接/二维码发送。
5. 确认电脑已经完整保存所有文件。
6. 返回备份页面，明确确认该批次。只有完成这一步，下次扫描才会跳过这些文件。

## 后续工作

- 旧网页下载页面仍会临时重启原生监听器；独立且可并发工作的网页网关监听器仍在规划中。
- 浏览器和原生备份目前以整个准备批次为单位确认。存储层已经支持部分确认，但传输结果界面尚未接入逐文件确认。
- 备份记录目前使用严格校验、按电脑档案分别存储并原子替换的 Manifest 文件；后续在超大媒体库场景下计划迁移到 SQLite。
- Android 长时间传输仍需接入专用前台服务生命周期，以保证息屏或后台运行时的可靠性。
- Windows 编译需要兼容 Flutter 的 Visual C++ 组件和真实插件符号链接。当前文档流程使用明确的 UAC 提权，不会开启或修改 Windows 开发者模式。
