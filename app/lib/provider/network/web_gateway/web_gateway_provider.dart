import 'dart:async';
import 'dart:io';

import 'package:common/isolate.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/web_gateway/web_gateway_state.dart';
import 'package:localsend_app/provider/network/web_gateway/controller/web_gateway_controller.dart';
import 'package:localsend_app/provider/network/web_gateway/controller/web_upload_controller.dart';
import 'package:localsend_app/provider/network/web_gateway/web_gateway_utils.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/simple_server.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('WebGateway');

/// Runs the independent web gateway listener.
///
/// The gateway owns its own HTTP listener on a separate LAN port so that
/// starting or stopping a web share never restarts or reconfigures the native
/// LocalSend server. The native server and the gateway can run concurrently.
/// The gateway serves both directions: web downloads (app -> browser) and web
/// uploads (browser -> app, with its own receive session).
final webGatewayProvider = NotifierProvider<WebGatewayService, WebGatewayState?>(
  (ref) => WebGatewayService(),
  onChanged: (_, next, ref) {
    for (final session in next?.receiveSessions.values ?? <ReceiveSessionState>[]) {
      ref.notifier(taskProvider).syncReceive(session);
    }
    // Keep the discovery "download" flag in sync with the gateway activity.
    // Only the download flag is owned by the gateway; the remaining sync
    // fields are maintained by serverProvider.onChanged.
    final syncState = ref.read(parentIsolateProvider).syncState;
    final download = next?.webSendState != null;
    if (syncState.download != download) {
      ref.redux(parentIsolateProvider).dispatch(IsolateSyncServerStateAction(
            alias: syncState.alias,
            port: syncState.port,
            protocol: syncState.protocol,
            serverRunning: syncState.serverRunning,
            download: download,
          ));
    }
  },
);

class WebGatewayService extends Notifier<WebGatewayState?> {
  late final WebGatewayUtils _utils = WebGatewayUtils(
    refFunc: () => ref,
    getState: () => state!,
    getStateOrNull: () => state,
    setState: (builder) => state = builder(state),
  );

  late final WebGatewayController _downloadController = WebGatewayController(_utils);
  late final WebUploadController _uploadController = WebUploadController(_utils);

  WebGatewayService();

  @override
  WebGatewayState? init() {
    return null;
  }

  /// Starts the gateway listener (if needed) and prepares a web download
  /// session for the given files. An already-running listener is reused so a
  /// web upload session keeps working.
  Future<WebGatewayState?> startWebSend({
    required List<CrossFile> files,
  }) async {
    await _ensureListener();
    await _downloadController.initializeWebSend(files: files);
    return state;
  }

  /// Starts the gateway listener (if needed) to accept browser uploads.
  Future<WebGatewayState?> startWebReceive() async {
    await _ensureListener();
    return state;
  }

  /// Closes the web download session. The listener stays up while a web
  /// receive session is active and is closed otherwise.
  Future<void> stopWebSend() async {
    _downloadController.cancelDownloads();
    state = state?.copyWith(webSendState: null);
    if (state?.receiveSession == null) {
      await _closeListener();
    }
  }

  /// Clears the web receive session. The listener stays up while a web
  /// download session is active and is closed otherwise.
  Future<void> stopWebReceive() async {
    _uploadController.cancelAll();
    state = state?.copyWith(
      receiveSession: null,
      receiveSessions: const {},
      receivePinAttempts: const {},
    );
    if (state?.webSendState == null) {
      await _closeListener();
    }
  }

  /// Stops the gateway listener and clears every web session.
  Future<void> stop() async {
    await _closeListener();
  }

  /// Ensures the gateway listener is bound and its routes installed.
  Future<WebGatewayState?> _ensureListener() async {
    final existing = state;
    if (existing != null) {
      return existing;
    }

    final router = SimpleServerRouteBuilder();
    final settings = ref.read(settingsProvider);
    final fingerprint = ref.read(securityProvider).certificateHash;

    final httpServer = await _bindAvailableHttpServer();
    _downloadController.installRoutes(
      router: router,
      alias: settings.alias,
      fingerprint: fingerprint,
    );
    _uploadController.installRoutes(
      router: router,
      port: httpServer.port,
    );
    final server = SimpleServer.start(server: httpServer, routes: router);

    state = WebGatewayState(
      httpServer: server,
      port: httpServer.port,
      webSendState: null,
      receiveSession: null,
      pinAttempts: {},
      receivePinAttempts: {},
    );

    _logger.info('Web gateway started. (Port: ${httpServer.port})');
    return state;
  }

  Future<void> _closeListener() async {
    _downloadController.cancelDownloads();
    _uploadController.cancelAll();
    final current = state;
    if (current == null) {
      return;
    }

    _logger.info('Stopping web gateway...');
    await current.httpServer.close();
    state = null;
    _logger.info('Web gateway stopped.');
  }

  /// Updates the web send pin.
  void setWebSendPin(String? pin) {
    state = state?.copyWith(
      webSendState: state?.webSendState?.copyWith(
        pin: pin,
      ),
    );
  }

  /// Updates the auto accept setting for web send.
  void setWebSendAutoAccept(bool autoAccept) {
    state = state?.copyWith(
      webSendState: state?.webSendState?.copyWith(
        autoAccept: autoAccept,
      ),
    );
  }

  /// Accepts the web send request.
  void acceptWebSendRequest(String sessionId) {
    _downloadController.acceptRequest(sessionId);
  }

  /// Declines the web send request.
  void declineWebSendRequest(String sessionId) {
    _downloadController.declineRequest(sessionId);
  }

  /// Accepts the pending browser upload request.
  void acceptWebReceiveRequest() {
    _uploadController.acceptRequest();
  }

  /// Declines the pending browser upload request.
  void declineWebReceiveRequest() {
    _uploadController.declineRequest();
  }

  /// Binds the gateway HTTP server. Port selection prefers the native port + 1,
  /// then a small deterministic range, and finally an OS-assigned port.
  Future<HttpServer> _bindAvailableHttpServer() async {
    final nativePort = ref.read(settingsProvider).port;
    final candidates = <int>[
      if (nativePort >= 0 && nativePort <= 65534) ...[
        nativePort + 1,
        for (var offset = 2; offset <= 26; offset++) nativePort + offset,
      ],
      0,
    ];

    Object? lastError;
    for (final port in candidates) {
      try {
        return await HttpServer.bind(InternetAddress.anyIPv4, port);
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError is Exception ? lastError : StateError('Could not bind a web gateway port.');
  }
}
