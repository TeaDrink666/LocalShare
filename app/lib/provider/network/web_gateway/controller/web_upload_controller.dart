import 'package:common/model/session_status.dart';
import 'package:localsend_app/features/backup/receiver/backup_receipt_coordinator.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/provider/network/server/controller/receive_controller.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/provider/network/web_gateway/web_gateway_utils.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/task_provider.dart';
import 'package:localsend_app/util/simple_server.dart';

/// Browser uploads share task execution and path preservation with native
/// uploads, while keeping their own listener and receive-session collection.
class WebUploadController {
  WebUploadController(this.gateway);
  final WebGatewayUtils gateway;
  ServerState _state() {
    final value = gateway.getState();
    return ServerState(
        httpServer: value.httpServer,
        alias: '',
        port: value.port,
        https: false,
        session: value.receiveSession,
        sessions: value.receiveSessions,
        pinAttempts: value.receivePinAttempts);
  }

  late final _controller = ReceiveController(
      ServerUtils(
          refFunc: gateway.refFunc,
          getState: _state,
          getStateOrNull: () => gateway.getStateOrNull() == null ? null : _state(),
          setState: (builder) {
            final changed = builder(gateway.getStateOrNull() == null ? null : _state());
            if (changed == null) return;
            gateway.setState(
                (old) => old?.copyWith(receiveSession: changed.session, receiveSessions: changed.sessions, receivePinAttempts: changed.pinAttempts));
            for (final session in changed.sessions.values) {
              gateway.ref.notifier(taskProvider).syncReceive(session);
            }
          }),
      backupReceiptCoordinator: BackupReceiptCoordinator());
  void installRoutes({required SimpleServerRouteBuilder router, required int port}) {
    final settings = gateway.ref.read(settingsProvider);
    _controller.installRoutes(
        router: router, alias: settings.alias, port: port, https: false, fingerprint: 'web-gateway', showToken: settings.showToken);
  }

  void acceptRequest() {
    final session = gateway.getStateOrNull()?.receiveSession;
    if (session == null) return;
    _controller.acceptFileRequest({for (final file in session.files.values) file.file.id: file.file.fileName});
  }

  void declineRequest() => _controller.declineFileRequest();
  void cancelAll() {
    for (final id in gateway.getStateOrNull()?.receiveSessions.keys.toList() ?? <String>[]) {
      final session = gateway.getStateOrNull()?.receiveSessions[id];
      if (session?.status == SessionStatus.waiting || session?.status == SessionStatus.sending) {
        _controller.controllerFor(id)?.cancelSession();
      } else {
        _controller.controllerFor(id)?.closeSession();
      }
    }
  }
}
