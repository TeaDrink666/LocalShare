# LocalShare

[English](README.md) | [简体中文](readme_i18n/README_ZH.md)

LocalShare is a local network file transfer and phone media backup tool for Windows and Android.

The project builds on LocalSend's local network transfer capabilities and focuses on everyday file transfers, browser transfers, and manual backups of phone photos and videos.

## Downloads

Download the Windows installer, portable package, and Android APKs from [LocalShare GitHub Releases](https://github.com/TeaDrink666/LocalShare/releases/latest).

## Features

- Send and receive files between Android and Windows over the local network.
- Manage transfers as tasks with progress, speed and time estimates; changing pages keeps tasks running.
- Run two transfers at once by default (configurable from 1 to 8), with additional tasks queued and media sync limited to one.
- Pause and resume native LocalShare transfers, keep task history, and preserve original names and folder structures in separate receive folders.
- Send or receive files in a browser through a link or QR code, without installing a client in the browser.
- Manually scan Android photos and videos and incrementally back them up to a selected Windows computer.
- Configure separate destinations for ordinary file transfers and phone backups.
- Store backed-up photos and videos in separate folders without preserving the original album directory structure.
- Verify received backups on Windows using temporary files, file sizes, SHA-256, atomic renaming, and SQLite receipt records.
- Update the phone's backup state only after Windows returns a verified receipt, without manually confirming that the backup succeeded.
- Avoid backing up the same files again when the user moves verified files from the Windows inbox to an archive.

## Backup behavior

Backups are manual incremental tasks. They do not include scheduled jobs, automatic background backups, cloud relays, or internet transfers.

The Windows backup destination is an inbox rather than a media library managed by the application. After a file is verified and its receipt is recorded, the user can move it elsewhere. Browser backups still require manual confirmation because a browser cannot prove where the Windows client ultimately saved the file.

See [docs/LOCALSHARE_ARCHITECTURE.md](docs/LOCALSHARE_ARCHITECTURE.md) for the architecture and protocol details.
See [docs/TASK_CENTER.md](docs/TASK_CENTER.md) for task scheduling, resume compatibility and current background limitations.

## Upgrading to 0.2.1

The official Android APK uses the project's fixed release signing identity. It can update the locally signed 0.2.0 build directly. GitHub releases 0.1.0 and 0.1.1 used a different Android signature: back up application settings and records before uninstalling the old app and installing 0.2.1. Later releases using the same identity can update in place.

Windows uses a self-signed code-signing certificate, so Windows may still show an untrusted publisher or SmartScreen message. The installer retains the same application identity for upgrades.

Release notes are in [CHANGELOG.md](CHANGELOG.md).

## Local builds

The project's build environment uses:

- Flutter 3.24.5
- Dart 3.5.x
- JDK 17
- Android SDK 34 and NDK 23.1.7779620
- Rust stable for the native `rhttp` dependency

Get dependencies from the `app` directory:

```powershell
cd app
flutter pub get
```

Build the Android ARM64 Release APK:

```powershell
flutter build apk --release --target-platform android-arm64
```

Official Android packages support `arm64-v8a` only.

If `android/key.properties` is absent, the build uses a development keystore to sign the Release APKs for testing. Configure your own keystore and `android/key.properties` for a fixed release signing identity. Signing keys and passwords must stay outside Git commits.

Build Windows Release:

```powershell
flutter build windows --release
```

To create a Windows installer, build Windows Release first, then compile [scripts/compile_localshare_setup.iss](scripts/compile_localshare_setup.iss) with Inno Setup.

If Windows cannot create plugin symbolic links, run [scripts/compile_windows_debug_localshare.ps1](scripts/compile_windows_debug_localshare.ps1) in an administrator PowerShell to prepare the dependencies.

## GitHub Actions

Pushing to `main` or manually starting the `LocalShare Build` workflow builds:

- Android `arm64-v8a` Release APK
- Windows x64 Release portable package
- Windows x64 Inno Setup installer

Download the packages from the workflow run's Artifacts. Local build caches, toolchains, signing files, and `dist` packages are excluded from Git.
These CI artifacts use development signing unless private signing configuration is supplied. Use the signed packages attached to GitHub Releases for official upgrades.

## Tests

Run these commands from the `app` directory:

```powershell
flutter analyze
flutter test
```

## License

This project follows the [LICENSE](LICENSE). It is derived from the open source LocalSend project. The original copyright and license information is retained in the repository history and source files.
