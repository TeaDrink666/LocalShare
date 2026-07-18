import 'dart:async';

import 'package:common/model/device.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/localshare_copy.dart';
import 'package:localsend_app/features/backup/data/android_media_catalog.dart';
import 'package:localsend_app/features/backup/data/backup_profile_store.dart';
import 'package:localsend_app/features/backup/data/backup_target_profile.dart';
import 'package:localsend_app/features/backup/domain/backup_plan.dart';
import 'package:localsend_app/features/backup/domain/incremental_backup_planner.dart';
import 'package:localsend_app/features/backup/manifest/manifest.dart';
import 'package:localsend_app/features/backup/presentation/backup_profile_epoch_guard.dart';
import 'package:localsend_app/features/backup/presentation/backup_saving_pop_scope.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/pages/web_send_page.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/localshare_design/localshare_page_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

typedef BackupProfileStoreOpener = Future<BackupProfileStore> Function();
typedef BackupMediaScanner = Future<AndroidMediaCatalogScan> Function({
  required bool includeImages,
  required bool includeVideos,
  required BackupScanProgress onProgress,
});
typedef BackupPermissionRequester = Future<BackupMediaPermissionResult>
    Function({
  required bool includeImages,
  required bool includeVideos,
});
typedef BackupWebSender = Future<void> Function(
  BuildContext context,
  List<CrossFile> files,
);
typedef BackupNearbyDeviceScanner = Future<void> Function(
  BuildContext context,
);
typedef BackupNativeSender = Future<BackupNativeTransferResult> Function(
  Device device,
  List<CrossFile> files,
  BackupManifest manifest,
);

class BackupPage extends StatefulWidget {
  final Future<void> Function() onOpenNativeTransfer;
  final Future<void> Function() onOpenReceive;
  final BackupProfileStoreOpener openStore;
  final bool? isAndroidOverride;
  final bool embedded;
  final BackupMediaScanner? scanMedia;
  final BackupPermissionRequester? requestPermission;
  final BackupWebSender? openWebSender;
  final BackupNearbyDeviceScanner? scanNearbyDevices;
  final BackupNativeSender? sendNativeBackup;
  final String Function()? sourceDeviceFingerprint;
  final NearbyDevicesState? nearbyDevicesOverride;

  const BackupPage({
    required this.onOpenNativeTransfer,
    required this.onOpenReceive,
    this.openStore = BackupProfileStore.openDefault,
    this.isAndroidOverride,
    this.embedded = false,
    this.scanMedia,
    this.requestPermission,
    this.openWebSender,
    this.scanNearbyDevices,
    this.sendNativeBackup,
    this.sourceDeviceFingerprint,
    this.nearbyDevicesOverride,
    super.key,
  });

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage>
    with Refena, AutomaticKeepAliveClientMixin {
  BackupProfileStore? _store;
  BackupProfileIndex? _profileIndex;
  BackupManifest? _pendingManifest;
  AndroidMediaCatalogScan? _catalogScan;
  BackupPlan? _plan;
  List<CrossFile> _plannedFiles = const [];

  bool _initializing = true;
  bool _scanning = false;
  bool _saving = false;
  bool _includeImages = true;
  bool _includeVideos = true;
  bool _limitedAccess = false;
  bool _permissionPermanentlyDenied = false;
  bool _allowManualConfirmation = false;
  int _scannedItemCount = 0;
  String? _backupResultMessage;
  String? _error;
  bool _initializationInFlight = false;
  final _profileEpoch = BackupProfileEpochGuard();

  BackupTargetProfile? get _selectedProfile => _profileIndex?.selectedProfile;
  bool get _isAndroid =>
      widget.isAndroidOverride ?? checkPlatform([TargetPlatform.android]);
  bool get _storageReady =>
      !_initializing && _store != null && _profileIndex != null;

  @override
  bool get wantKeepAlive => widget.embedded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    if (_initializationInFlight) {
      return;
    }
    _initializationInFlight = true;
    _profileEpoch.invalidate();
    if (mounted) {
      setState(() {
        _initializing = true;
        _store = null;
        _profileIndex = null;
        _pendingManifest = null;
        _catalogScan = null;
        _plan = null;
        _plannedFiles = const [];
        _saving = false;
        _scanning = false;
        _allowManualConfirmation = false;
        _backupResultMessage = null;
        _error = null;
      });
    }
    if (!_isAndroid) {
      if (mounted) {
        setState(() => _initializing = false);
      }
      _initializationInFlight = false;
      return;
    }

    try {
      final store = await widget.openStore();
      await store.ensureDefaultProfile(LocalShareCopy.defaultBackupTarget);
      final index = await store.loadIndex();
      final pending = index.selectedProfile == null
          ? null
          : await store.loadPending(index.selectedProfile!.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _store = store;
        _profileIndex = index;
        _pendingManifest = pending;
        _initializing = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _store = null;
          _profileIndex = null;
          _pendingManifest = null;
          _error = '${LocalShareCopy.backupStorageUnavailable}\n$error';
          _initializing = false;
        });
      }
    } finally {
      _initializationInFlight = false;
    }
  }

  Future<void> _selectProfile(String profileId) async {
    final store = _store;
    if (!_storageReady || store == null || _saving || _scanning) {
      return;
    }
    final profileEpoch = _profileEpoch.invalidate();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await store.selectProfile(profileId);
      final index = await store.loadIndex();
      final pending = await store.loadPending(profileId);
      if (!mounted ||
          !_profileEpoch.matches(
            epoch: profileEpoch,
            profileId: profileId,
            selectedProfileId: index.selectedProfile?.id,
          )) {
        return;
      }
      setState(() {
        _profileIndex = index;
        _pendingManifest = pending;
        _catalogScan = null;
        _plan = null;
        _plannedFiles = const [];
        _limitedAccess = false;
        _permissionPermanentlyDenied = false;
        _allowManualConfirmation = false;
        _backupResultMessage = null;
      });
    } catch (error) {
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _createProfile() async {
    if (!_storageReady || _saving || _scanning || _store == null) {
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(LocalShareCopy.newBackupTarget),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: LocalShareCopy.computerName,
            prefixIcon: const Icon(Icons.computer_rounded),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(dialogContext).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(LocalShareCopy.cancel),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.of(dialogContext).pop(value);
              }
            },
            child: Text(LocalShareCopy.create),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted || _store == null) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final profileEpoch = _profileEpoch.invalidate();
    try {
      await _store!.createProfile(name);
      final index = await _store!.loadIndex();
      if (!mounted || !_profileEpoch.owns(profileEpoch)) {
        return;
      }
      setState(() {
        _profileIndex = index;
        _pendingManifest = null;
        _catalogScan = null;
        _plan = null;
        _plannedFiles = const [];
        _limitedAccess = false;
        _permissionPermanentlyDenied = false;
        _allowManualConfirmation = false;
        _backupResultMessage = null;
      });
    } catch (error) {
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _scan() async {
    final profile = _selectedProfile;
    final store = _store;
    if (!_storageReady ||
        profile == null ||
        store == null ||
        _scanning ||
        _saving) {
      return;
    }
    if (!_includeImages && !_includeVideos) {
      return;
    }

    setState(() {
      _scanning = true;
      _scannedItemCount = 0;
      _error = null;
      _limitedAccess = false;
      _permissionPermanentlyDenied = false;
      _allowManualConfirmation = false;
      _backupResultMessage = null;
      _catalogScan = null;
      _plan = null;
      _plannedFiles = const [];
    });
    try {
      final permissionResult = await (widget.requestPermission?.call(
            includeImages: _includeImages,
            includeVideos: _includeVideos,
          ) ??
          _requestMediaPermission(
            includeImages: _includeImages,
            includeVideos: _includeVideos,
          ));
      if (!permissionResult.allowed) {
        if (mounted) {
          setState(() {
            _permissionPermanentlyDenied = permissionResult.permanentlyDenied;
          });
        }
        throw _BackupUiException(LocalShareCopy.mediaPermissionDenied);
      }

      void onProgress(int count) {
        if (mounted) {
          setState(() => _scannedItemCount = count);
        }
      }

      final scan = await (widget.scanMedia?.call(
            includeImages: _includeImages,
            includeVideos: _includeVideos,
            onProgress: onProgress,
          ) ??
          const AndroidMediaCatalog().scan(
            includeImages: _includeImages,
            includeVideos: _includeVideos,
            onProgress: onProgress,
          ));
      final ledger = await store.loadConfirmedLedger(profile.id);
      final completePlan = const IncrementalBackupPlanner().createPlan(
        currentSnapshot: scan.snapshot,
        confirmedLedger: ledger,
      );
      final plan = _planForPendingBatch(completePlan, _pendingManifest);
      final files = scan.crossFilesForPlan(plan);
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogScan = scan;
        _plan = plan;
        _plannedFiles = files;
        _limitedAccess = permissionResult.limited;
      });
      final nearbyDevices = (widget.nearbyDevicesOverride?.devices ??
              ref.read(nearbyDevicesProvider).devices)
          .values
          .where(_isBackupTargetDevice);
      if (files.isNotEmpty && nearbyDevices.isEmpty) {
        unawaited(_scanNearbyDevices());
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == 'MEDIA_PERMISSION_DENIED'
              ? LocalShareCopy.mediaPermissionDenied
              : '${LocalShareCopy.scanFailed}: ${error.message ?? error.code}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is _BackupUiException
              ? error.message
              : '${LocalShareCopy.scanFailed}: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  void _setMediaScope({bool? includeImages, bool? includeVideos}) {
    setState(() {
      _includeImages = includeImages ?? _includeImages;
      _includeVideos = includeVideos ?? _includeVideos;
      _catalogScan = null;
      _plan = null;
      _plannedFiles = const [];
      _limitedAccess = false;
      _permissionPermanentlyDenied = false;
      _scannedItemCount = 0;
      _error = null;
    });
  }

  Future<BackupManifest?> _stagePending(
    BackupPlan plan, {
    required BackupTargetProfile profile,
    required int expectedProfileEpoch,
  }) async {
    final store = _store;
    if (plan.isEmpty || store == null) {
      return null;
    }

    final sourceDevice = widget.sourceDeviceFingerprint?.call() ??
        ref.read(deviceFullInfoProvider).fingerprint;
    final manifest = BackupManifest.fromMediaItems(
      batchId: _uuid.v4(),
      profileId: profile.id,
      sourceDevice: sourceDevice,
      createdAtUtc: DateTime.now().toUtc(),
      items: plan.items.map((item) => item.snapshotItem),
    );
    await store.savePending(manifest);
    if (mounted &&
        _profileEpoch.matches(
          epoch: expectedProfileEpoch,
          profileId: profile.id,
          selectedProfileId: _selectedProfile?.id,
        )) {
      setState(() => _pendingManifest = manifest);
    }
    return manifest;
  }

  Future<BackupManifest?> _ensurePending(
    BackupPlan plan, {
    required BackupTargetProfile profile,
    required int expectedProfileEpoch,
  }) async {
    final existing = _pendingManifest;
    if (existing != null && existing.profileId == profile.id) {
      if (!_manifestMatchesPlan(existing, plan)) {
        throw _BackupUiException(LocalShareCopy.pendingBatchChanged);
      }
      return existing;
    }
    return _stagePending(
      plan,
      profile: profile,
      expectedProfileEpoch: expectedProfileEpoch,
    );
  }

  Future<void> _sendViaWeb() async {
    final plan = _plan;
    final profile = _selectedProfile;
    if (!_storageReady ||
        profile == null ||
        plan == null ||
        _plannedFiles.isEmpty ||
        _saving ||
        _scanning) {
      return;
    }
    final files = List<CrossFile>.unmodifiable(_plannedFiles);
    final profileEpoch = _profileEpoch.capture();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final manifest = await _ensurePending(
        plan,
        profile: profile,
        expectedProfileEpoch: profileEpoch,
      );
      if (manifest == null ||
          !mounted ||
          !_profileEpoch.matches(
            epoch: profileEpoch,
            profileId: profile.id,
            selectedProfileId: _selectedProfile?.id,
          )) {
        return;
      }
      final customWebSender = widget.openWebSender;
      if (customWebSender != null) {
        await customWebSender(context, files);
      } else {
        await context.push(() => WebSendPage(files));
      }
      if (!mounted ||
          !_profileEpoch.matches(
            epoch: profileEpoch,
            profileId: profile.id,
            selectedProfileId: _selectedProfile?.id,
          )) {
        return;
      }

      setState(() {
        _allowManualConfirmation = true;
        _backupResultMessage = null;
      });

      // Keep pending actions serialized until the durable batch has been
      // re-read. Releasing the page earlier would let a confirm/discard race
      // this load and reintroduce an already resolved manifest into the UI.
      await _reloadPending(
        profileId: manifest.profileId,
        expectedProfileEpoch: profileEpoch,
      );
    } catch (error) {
      if (mounted &&
          _profileEpoch.matches(
            epoch: profileEpoch,
            profileId: profile.id,
            selectedProfileId: _selectedProfile?.id,
          )) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _sendToDevice(Device device) async {
    final plan = _plan;
    final selectedProfile = _selectedProfile;
    final store = _store;
    if (!_storageReady ||
        selectedProfile == null ||
        store == null ||
        plan == null ||
        _plannedFiles.isEmpty ||
        _saving ||
        _scanning) {
      return;
    }

    final files = List<CrossFile>.unmodifiable(_plannedFiles);
    final profileEpoch = _profileEpoch.capture();
    setState(() {
      _saving = true;
      _allowManualConfirmation = false;
      _backupResultMessage = null;
      _error = null;
    });
    try {
      final profile = await _bindProfileToDevice(selectedProfile, device);
      if (profile == null || !mounted) {
        return;
      }
      final manifest = await _ensurePending(
        plan,
        profile: profile,
        expectedProfileEpoch: profileEpoch,
      );
      if (manifest == null ||
          !mounted ||
          !_profileEpoch.matches(
            epoch: profileEpoch,
            profileId: profile.id,
            selectedProfileId: _selectedProfile?.id,
          )) {
        return;
      }
      final result = await (widget.sendNativeBackup?.call(
            device,
            files,
            manifest,
          ) ??
          ref.notifier(sendProvider).startBackupSession(
                target: device,
                files: files,
                manifest: manifest,
              ));
      if (!mounted ||
          !_profileEpoch.matches(
            epoch: profileEpoch,
            profileId: profile.id,
            selectedProfileId: _selectedProfile?.id,
          )) {
        return;
      }
      final confirmedCount = await store.confirmPending(
        profile.id,
        mediaKeys: result.committedMediaKeys,
      );
      await _reloadProfilesAndPending();
      await _recalculatePlan();
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() {
          _backupResultMessage = LocalShareCopy.computerVerifiedItems(
            confirmedCount,
            result.remainingItemCount,
          );
          if (result.errorMessage != null && result.remainingItemCount > 0) {
            _error = result.errorMessage;
          }
        });
      }
    } catch (error) {
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() {
          _error = error is BackupProtocolUnavailableException
              ? LocalShareCopy.backupProtocolUnavailable
              : error.toString();
        });
      }
    } finally {
      if (mounted && _profileEpoch.owns(profileEpoch)) {
        setState(() => _saving = false);
      }
    }
  }

  Future<BackupTargetProfile?> _bindProfileToDevice(
    BackupTargetProfile profile,
    Device device,
  ) async {
    final store = _store;
    if (store == null) {
      return null;
    }

    final linkedFingerprint = profile.deviceFingerprint;
    if (linkedFingerprint != null && linkedFingerprint != device.fingerprint) {
      setState(() {
        _error = LocalShareCopy.backupTargetMismatch(
          profile.displayName,
          device.alias,
        );
      });
      return null;
    }

    BackupTargetProfile? deviceProfile;
    for (final candidate in _profileIndex?.profiles ?? const []) {
      if (candidate.deviceFingerprint == device.fingerprint) {
        deviceProfile = candidate;
        break;
      }
    }
    if (deviceProfile != null && deviceProfile.id != profile.id) {
      setState(() {
        _error = LocalShareCopy.deviceAlreadyHasBackupTarget(
          device.alias,
          deviceProfile!.displayName,
        );
      });
      return null;
    }

    if (linkedFingerprint != null) {
      return profile;
    }

    final bound = await store.bindProfileToDevice(
      profileId: profile.id,
      deviceFingerprint: device.fingerprint,
    );
    final index = await store.loadIndex();
    if (mounted) {
      setState(() => _profileIndex = index);
    }
    return bound;
  }

  Future<void> _confirmPending() async {
    final pending = _pendingManifest;
    final profile = _selectedProfile;
    final store = _store;
    if (pending == null ||
        profile == null ||
        store == null ||
        !_allowManualConfirmation ||
        _saving ||
        _scanning) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_rounded),
        title: Text(LocalShareCopy.confirmSavedTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(LocalShareCopy.confirmSavedMessage),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _ConfirmationDetailRow(
                    key: const Key('backup-confirm-target'),
                    label: LocalShareCopy.confirmationTargetComputer,
                    value: profile.displayName,
                  ),
                  const SizedBox(height: 9),
                  _ConfirmationDetailRow(
                    key: const Key('backup-confirm-count'),
                    label: LocalShareCopy.confirmationItemCount,
                    value: LocalShareCopy.itemCount(pending.itemCount),
                  ),
                  const SizedBox(height: 9),
                  _ConfirmationDetailRow(
                    key: const Key('backup-confirm-size'),
                    label: LocalShareCopy.confirmationTotalSize,
                    value: pending.totalBytes.asReadableFileSize,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LocalShareCopy.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_rounded),
            label: Text(LocalShareCopy.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final count = await store.confirmPending(profile.id);
      await _reloadProfilesAndPending();
      await _recalculatePlan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocalShareCopy.confirmedItems(count))),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _discardPending() async {
    final profile = _selectedProfile;
    if (profile == null || _store == null || _saving || _scanning) {
      return;
    }
    setState(() => _saving = true);
    try {
      await _store!.discardPending(profile.id);
      if (mounted) {
        setState(() {
          _pendingManifest = null;
          _allowManualConfirmation = false;
          _backupResultMessage = null;
        });
        await _recalculatePlan();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _reloadPending({
    required String profileId,
    required int expectedProfileEpoch,
  }) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final pending = await store.loadPending(profileId);
    if (mounted &&
        _profileEpoch.matches(
          epoch: expectedProfileEpoch,
          profileId: profileId,
          selectedProfileId: _selectedProfile?.id,
        )) {
      setState(() => _pendingManifest = pending);
    }
  }

  Future<void> _reloadProfilesAndPending() async {
    final store = _store;
    if (store == null) {
      return;
    }
    final index = await store.loadIndex();
    final pending = index.selectedProfile == null
        ? null
        : await store.loadPending(index.selectedProfile!.id);
    if (mounted) {
      setState(() {
        _profileIndex = index;
        _pendingManifest = pending;
      });
    }
  }

  Future<void> _recalculatePlan() async {
    final scan = _catalogScan;
    final profile = _selectedProfile;
    final store = _store;
    if (scan == null || profile == null || store == null) {
      return;
    }
    final ledger = await store.loadConfirmedLedger(profile.id);
    final completePlan = const IncrementalBackupPlanner().createPlan(
      currentSnapshot: scan.snapshot,
      confirmedLedger: ledger,
    );
    final plan = _planForPendingBatch(completePlan, _pendingManifest);
    final files = scan.crossFilesForPlan(plan);
    if (mounted) {
      setState(() {
        _plan = plan;
        _plannedFiles = files;
      });
    }
  }

  Future<void> _scanNearbyDevices() async {
    final customScanner = widget.scanNearbyDevices;
    if (customScanner != null) {
      await customScanner(context);
      return;
    }
    await context.global.dispatchAsync(StartSmartScan(forceLegacy: true));
  }

  Future<BackupMediaPermissionResult> _requestMediaPermission({
    required bool includeImages,
    required bool includeVideos,
  }) async {
    final sdk = ref.read(deviceInfoProvider).androidSdkInt ?? 0;
    if (sdk >= 33) {
      final permissions = <Permission>[
        if (includeImages) Permission.photos,
        if (includeVideos) Permission.videos,
      ];
      final statuses = await permissions.request();
      final values = statuses.values;
      return BackupMediaPermissionResult(
        allowed: values.every(
          (status) => status.isGranted || status.isLimited,
        ),
        limited: values.any((status) => status.isLimited),
        permanentlyDenied: values.any((status) => status.isPermanentlyDenied),
      );
    }

    final status = await Permission.storage.request();
    return BackupMediaPermissionResult(
      allowed: status.isGranted || status.isLimited,
      limited: status.isLimited,
      permanentlyDenied: status.isPermanentlyDenied,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final compactEmbeddedAndroid = widget.embedded && _isAndroid;
    final content = SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          compactEmbeddedAndroid ? 14 : 18,
          compactEmbeddedAndroid ? 12 : 18,
          compactEmbeddedAndroid ? 14 : 18,
          40,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compactEmbeddedAndroid) ...[
                  const _BackupHero(),
                  const SizedBox(height: 16),
                ],
                if (_isAndroid) _buildAndroidBody() else _buildDesktopBody(),
              ],
            ),
          ),
        ),
      ),
    );
    final page = Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(LocalShareCopy.backupPageTitle)),
      body:
          widget.embedded ? content : LocalSharePageBackground(child: content),
    );
    if (widget.embedded) {
      return page;
    }
    return BackupSavingPopScope(saving: _saving, child: page);
  }

  Widget _buildAndroidBody() {
    if (_initializing) {
      return const _LoadingCard();
    }
    if (!_storageReady) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InlineNotice(
            icon: Icons.error_outline_rounded,
            text: _error ?? LocalShareCopy.scanFailed,
            isError: true,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _initialize,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(LocalShareCopy.retry),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackupSetupCard(
          key: const Key('backup-setup-card'),
          profiles: _profileIndex?.profiles ?? const [],
          selectedProfile: _selectedProfile,
          enabled: _storageReady && !_saving && !_scanning,
          onSelected: _selectProfile,
          onAdd: _createProfile,
          includeImages: _includeImages,
          includeVideos: _includeVideos,
          scanning: _scanning,
          busy: !_storageReady || _saving,
          scannedItemCount: _scannedItemCount,
          onImagesChanged: (value) => _setMediaScope(includeImages: value),
          onVideosChanged: (value) => _setMediaScope(includeVideos: value),
          onScan: _scan,
        ),
        if (_pendingManifest != null) ...[
          const SizedBox(height: 10),
          _PendingConfirmationCard(
            manifest: _pendingManifest!,
            busy: _saving || _scanning,
            allowManualConfirmation: _allowManualConfirmation,
            onConfirm: _confirmPending,
            onDiscard: _discardPending,
          ),
        ],
        if (_limitedAccess) ...[
          const SizedBox(height: 10),
          _InlineNotice(
            icon: Icons.photo_library_outlined,
            text: LocalShareCopy.limitedMediaAccess,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          _InlineNotice(
            icon: Icons.error_outline_rounded,
            text: _error!,
            isError: true,
          ),
          if (_permissionPermanentlyDenied) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () async => openAppSettings(),
                icon: const Icon(Icons.settings_rounded),
                label: Text(LocalShareCopy.openSettings),
              ),
            ),
          ],
        ],
        if (_backupResultMessage != null) ...[
          const SizedBox(height: 10),
          _InlineNotice(
            icon: Icons.verified_rounded,
            text: _backupResultMessage!,
          ),
        ],
        if (_plan != null) ...[
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: _plan!.isEmpty
                ? _AllBackedUpCard(
                    key: const ValueKey('empty'),
                    plan: _plan!,
                  )
                : _BackupPlanCard(
                    key: const ValueKey('plan'),
                    plan: _plan!,
                    nearbyState: widget.nearbyDevicesOverride ??
                        context.watch(nearbyDevicesProvider),
                    busy: !_storageReady || _saving || _scanning,
                    onDevice: _sendToDevice,
                    onRefreshDevices: _scanNearbyDevices,
                    onWeb: _sendViaWeb,
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopBody() {
    final scheme = Theme.of(context).colorScheme;
    final action = FilledButton.tonalIcon(
      onPressed: () async {
        await widget.onOpenReceive();
        if (mounted && !widget.embedded) {
          context.pop();
        }
      },
      icon: const Icon(Icons.download_rounded),
      label: Text(LocalShareCopy.goToReceive),
    );
    final message = Row(
      children: [
        Icon(Icons.phone_android_rounded, color: scheme.primary, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            LocalShareCopy.startOnAndroid,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
    return _SurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                message,
                const SizedBox(height: 14),
                action,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: message),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _BackupHero extends StatelessWidget {
  const _BackupHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            Icons.photo_library_outlined,
            color: scheme.onPrimaryContainer,
            size: 23,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocalShareCopy.backupPageTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                LocalShareCopy.backupPageSubtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 180,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _BackupSetupCard extends StatelessWidget {
  const _BackupSetupCard({
    required this.profiles,
    required this.selectedProfile,
    required this.enabled,
    required this.onSelected,
    required this.onAdd,
    required this.includeImages,
    required this.includeVideos,
    required this.scanning,
    required this.busy,
    required this.scannedItemCount,
    required this.onImagesChanged,
    required this.onVideosChanged,
    required this.onScan,
    super.key,
  });

  final List<BackupTargetProfile> profiles;
  final BackupTargetProfile? selectedProfile;
  final bool enabled;
  final ValueChanged<String> onSelected;
  final VoidCallback onAdd;
  final bool includeImages;
  final bool includeVideos;
  final bool scanning;
  final bool busy;
  final int scannedItemCount;
  final ValueChanged<bool> onImagesChanged;
  final ValueChanged<bool> onVideosChanged;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canScan = !scanning && !busy && (includeImages || includeVideos);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: LocalShareCopy.backupTarget,
                child: Icon(
                  Icons.computer_outlined,
                  color: scheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedProfile?.id,
                    isExpanded: true,
                    isDense: true,
                    borderRadius: BorderRadius.circular(14),
                    hint: Text(LocalShareCopy.backupTarget),
                    items: profiles
                        .map(
                          (profile) => DropdownMenuItem(
                            value: profile.id,
                            child: Text(
                              profile.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: enabled
                        ? (value) {
                            if (value != null) {
                              onSelected(value);
                            }
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: LocalShareCopy.addBackupTarget,
                onPressed: enabled ? onAdd : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Divider(height: 20, color: scheme.outlineVariant),
          Text(
            LocalShareCopy.mediaScope,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilterChip(
                selected: includeImages,
                onSelected: scanning || busy ? null : onImagesChanged,
                avatar: const Icon(Icons.photo_rounded, size: 18),
                label: Text(LocalShareCopy.photos),
              ),
              FilterChip(
                selected: includeVideos,
                onSelected: scanning || busy ? null : onVideosChanged,
                avatar: const Icon(Icons.videocam_rounded, size: 18),
                label: Text(LocalShareCopy.videos),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (scanning) ...[
            Text(
              LocalShareCopy.scanningItems(scannedItemCount),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 7),
            const LinearProgressIndicator(),
          ] else
            FilledButton.icon(
              key: const Key('backup-scan-button'),
              onPressed: canScan ? onScan : null,
              icon: const Icon(Icons.radar_rounded),
              label: Text(LocalShareCopy.scanForChanges),
            ),
        ],
      ),
    );
  }
}

class _ConfirmationDetailRow extends StatelessWidget {
  const _ConfirmationDetailRow({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

class _PendingConfirmationCard extends StatelessWidget {
  const _PendingConfirmationCard({
    required this.manifest,
    required this.busy,
    required this.allowManualConfirmation,
    required this.onConfirm,
    required this.onDiscard,
  });

  final BackupManifest manifest;
  final bool busy;
  final bool allowManualConfirmation;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.tertiary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                allowManualConfirmation
                    ? Icons.info_outline_rounded
                    : Icons.cloud_done_outlined,
                color: scheme.tertiary,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allowManualConfirmation
                          ? LocalShareCopy.pendingConfirmation
                          : LocalShareCopy.pendingComputerReceipt,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      allowManualConfirmation
                          ? LocalShareCopy.pendingConfirmationDescription(
                              manifest.itemCount,
                            )
                          : LocalShareCopy.pendingComputerReceiptDescription(
                              manifest.itemCount,
                            ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                '${LocalShareCopy.itemCount(manifest.itemCount)} · ${manifest.totalBytes.asReadableFileSize}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              TextButton(
                onPressed: busy ? null : onDiscard,
                child: Text(LocalShareCopy.discardPending),
              ),
              if (allowManualConfirmation)
                FilledButton.icon(
                  onPressed: busy ? null : onConfirm,
                  icon: const Icon(Icons.verified_rounded),
                  label: Text(LocalShareCopy.confirmSaved),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackupPlanCard extends StatelessWidget {
  const _BackupPlanCard({
    super.key,
    required this.plan,
    required this.nearbyState,
    required this.busy,
    required this.onDevice,
    required this.onRefreshDevices,
    required this.onWeb,
  });

  final BackupPlan plan;
  final NearbyDevicesState nearbyState;
  final bool busy;
  final Future<void> Function(Device device) onDevice;
  final Future<void> Function() onRefreshDevices;
  final Future<void> Function() onWeb;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = nearbyState.devices.values
        .where(_isBackupTargetDevice)
        .toList(growable: false)
      ..sort((left, right) => left.alias.compareTo(right.alias));
    final scanningDevices =
        nearbyState.runningFavoriteScan || nearbyState.runningIps.isNotEmpty;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                LocalShareCopy.backupReady,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              );
              final summary = Text(
                '${LocalShareCopy.itemCount(plan.plannedItemCount)} · ${plan.totalBytes.asReadableFileSize}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: scheme.primary),
              );
              if (constraints.maxWidth < 400) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 3),
                    summary,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  Flexible(child: summary),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            key: const Key('backup-nearby-section'),
            children: [
              Expanded(
                child: Text(
                  LocalShareCopy.nearbyComputers,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: LocalShareCopy.refreshNearbyDevices,
                onPressed: busy || scanningDevices
                    ? null
                    : () async => onRefreshDevices(),
                icon: scanningDevices
                    ? const SizedBox.square(
                        dimension: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (devices.isEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.radar_rounded,
                    size: 21,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      scanningDevices
                          ? LocalShareCopy.findingNearbyDevices
                          : LocalShareCopy.noNearbyComputers,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          else
            ...devices.map(
              (device) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _BackupDeviceTile(
                  device: device,
                  enabled: !busy,
                  onTap: () async => onDevice(device),
                ),
              ),
            ),
          Divider(height: 18, color: scheme.outlineVariant),
          InkWell(
            key: const Key('backup-web-send'),
            borderRadius: BorderRadius.circular(13),
            onTap: busy ? null : () async => onWeb(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, color: scheme.primary),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      LocalShareCopy.backupViaLink,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupDeviceTile extends StatelessWidget {
  const _BackupDeviceTile({
    required this.device,
    required this.enabled,
    required this.onTap,
  });

  final Device device;
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withOpacity(0.48),
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        dense: true,
        enabled: enabled,
        onTap: () async => onTap(),
        leading: Icon(device.deviceType.icon, color: scheme.primary),
        title: Text(
          device.alias,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (device.deviceModel?.trim().isNotEmpty ?? false)
              device.deviceModel!.trim(),
            device.ip,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.send_rounded, size: 19),
      ),
    );
  }
}

class _AllBackedUpCard extends StatelessWidget {
  const _AllBackedUpCard({
    super.key,
    required this.plan,
  });

  final BackupPlan plan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.done_all_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.currentItemCount == 0
                      ? LocalShareCopy.noVisibleMedia
                      : LocalShareCopy.everythingBackedUp,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  plan.currentItemCount == 0
                      ? LocalShareCopy.noVisibleMediaDescription
                      : LocalShareCopy.everythingBackedUpDescription,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = isError ? scheme.error : scheme.onSecondaryContainer;
    final background =
        isError ? scheme.errorContainer : scheme.secondaryContainer;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background.withOpacity(0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.58)),
      ),
      child: child,
    );
  }
}

final class BackupMediaPermissionResult {
  const BackupMediaPermissionResult({
    required this.allowed,
    required this.limited,
    required this.permanentlyDenied,
  });

  final bool allowed;
  final bool limited;
  final bool permanentlyDenied;
}

final class _BackupUiException implements Exception {
  const _BackupUiException(this.message);

  final String message;
}

BackupPlan _planForPendingBatch(
  BackupPlan completePlan,
  BackupManifest? pending,
) {
  if (pending == null) {
    return completePlan;
  }

  final plannedByKey = {
    for (final item in completePlan.items) item.snapshotItem.mediaKey: item,
  };
  final pendingItems = <BackupPlanItem>[];
  for (final manifestItem in pending.items) {
    final snapshot = manifestItem.snapshotItem;
    final planned = plannedByKey[snapshot.mediaKey];
    if (planned == null || planned.snapshotItem != snapshot) {
      throw _BackupUiException(LocalShareCopy.pendingBatchChanged);
    }
    pendingItems.add(planned);
  }

  return BackupPlan(
    items: pendingItems,
    currentItemCount: pendingItems.length,
    unchangedItemCount: 0,
    ledgerOnlyItemCount: 0,
  );
}

bool _manifestMatchesPlan(BackupManifest manifest, BackupPlan plan) {
  if (manifest.itemCount != plan.plannedItemCount) {
    return false;
  }
  final plannedByKey = {
    for (final item in plan.items)
      item.snapshotItem.mediaKey: item.snapshotItem,
  };
  return manifest.items.every((item) {
    final snapshot = item.snapshotItem;
    return plannedByKey[snapshot.mediaKey] == snapshot;
  });
}

bool _isBackupTargetDevice(Device device) {
  return switch (device.deviceType) {
    DeviceType.desktop || DeviceType.headless || DeviceType.server => true,
    DeviceType.mobile || DeviceType.web => false,
  };
}
