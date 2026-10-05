# LocalShare 文件检查与清理记录

检查日期：2026-10-04。范围：当前本地项目目录。按用户选择保留可重建的构建缓存。

## 已清理

| 内容 | 处理与依据 |
| --- | --- |
| `readme_i18n/README_*.md` 中的其他 17 种语言 | 删除；英文保留在根目录 `README.md`，中文保留在 `readme_i18n/README_ZH.md`。 |
| 旧版中文 README | 替换为当前 LocalShare 的中文说明；原文件介绍 LocalSend，下载、反馈和贡献链接指向原项目。中英文说明现在描述同一项目。 |
| `.github/workflows/winget.yml` | 删除遗留自动发布任务；它使用 `LocalSend.LocalSend` 标识，与 LocalShare 不匹配，此前发布时也因缺少 token 失败。随 0.2.1 源码发布。 |
| `LocalShare/cmdline-tools-extracted/` | 删除解压副本；其中 104 个文件与已安装的 `LocalShare/android-sdk/cmdline-tools/latest/` 逐文件 SHA-256 一致。 |
| `LocalShare/downloads/commandlinetools-win-11076708_latest.zip` | 删除重复安装下载包；ZIP 内的 104 个文件也与已安装版本逐文件 SHA-256 一致。 |
| `LocalShare/downloads/innosetup-6.exe` | 删除失效下载；该文件只有 10,392 字节，文件头为 HTML，不是 Windows 可执行程序。有效的 `innosetup-6.7.3.exe` 保留。 |
| 原用户目录中的签名文件 | 清理旧副本和空目录；清理前核对密钥库、公开证书和密码与项目内 `.signing/` 副本完全一致。 |

以上重复工具文件和文档约释放 293 MiB。

## 保留的内容

| 内容 | 保留理由 |
| --- | --- |
| `app/build/`，约 11.5 GiB | 构建输出与缓存，按用户选择保留。 |
| `app/.dart_tool/`，约 242 MiB；`app/android/.gradle/`，约 31 MiB | 依赖解析、生成代码和 Gradle 缓存，按用户选择保留。 |
| `LocalShare/flutter-3.24.5/`、`android-sdk/`、`gradle-home/` | 本地 Windows/Android 构建脚本直接使用这些工具和缓存。 |
| `LocalShare/inno-setup-6/` 与有效安装程序 | Windows 安装包编译工具与有效的安装来源。 |
| `LocalShare/kotlin-check/`、`windows-build-logs/` | 编译验证依赖、生成验证结果和构建日志；与用户选择保留构建缓存一致。 |
| `dist/` 内的旧安装包、调试包 | 可用于安装、验证和回退；没有仅凭版本较旧就删除。 |
| `.signing/` | 当前签名密钥、密码、配置和证书信息。整个目录已被 Git 忽略，没有文件被 Git 跟踪。 |
| `app/lib/`、`common/`、`cli/`、测试、许可证、应用内翻译、其他平台源码 | 仍属于源码、测试、法律信息或有明确引用关系的资源。README 的语言精简不涉及应用内翻译。 |

按内容检查了 768 个受 Git 管理的非空普通文件，发现 15 组相同内容。主要是不同平台或不同资源名称要求的图标，以及 Xcode 工作区配置；内容相同不足以证明这些文件无用，均保留。

## 仍需整理的历史内容

| 内容 | 发现的问题 |
| --- | --- |
| `CONTRIBUTING.md` | 仍介绍 LocalSend，包含原项目的反馈、发行渠道与贡献流程；适合改写成 LocalShare 的贡献说明。 |
| `fastlane/metadata/android/` | 应用商店描述和截图仍是 LocalSend 的历史资料；未来若发布到商店，应更新后再使用。 |
| `.github/workflows/release.yml` | 旧发行链路包含 `ubuntu-20.04`、额外签名 Secrets 和 LocalSend 产物名称；当前 LocalShare 的 Windows/Android 构建使用 `localshare-build.yml`。 |
| `.github/release-drafter.yml` | 完整更新日志链接仍指向 LocalSend 原项目。 |
| `docs/LOCALSHARE_DEVELOPMENT.md` | 工具目录描述为 `D:\software_D\LocalShare`，目前构建助手使用项目内的 `LocalShare/`。两处目录均存在，需要统一后才能进一步合并工具链。 |
| 其他平台的构建脚本及 `submodules/flutter` | 旧脚本仍引用该 Flutter 子模块，不能只根据目录看似闲置就删除。 |

这些历史内容本次列出问题，保留有引用关系的文件，避免把文档过时或平台暂不发布直接当作源码无用。

## 验证

- 仅保留英文主 README 和中文 README，文档内的本地链接目标存在。
- 17 种已删除语言的 README 链接无残留。
- Git 忽略 `.signing/` 中的全部 8 个文件，签名目录没有被跟踪的文件。
- 原签名目录已删除，项目内的密钥库、密码和公开证书保留。
- 构建缓存、实际使用的工具链、源码和测试保留。
- 对本次文档改动执行 `git diff --check`，没有空白错误；未重新编译应用。
