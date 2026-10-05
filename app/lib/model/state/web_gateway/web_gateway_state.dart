import 'package:localsend_app/model/state/send/web/web_send_state.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/util/simple_server.dart';

/// State of the independent web gateway listener.
///
/// The gateway runs on its own LAN port so that starting or stopping a web
/// share never restarts or reconfigures the native LocalSend server.
const _unset = Object();

class WebGatewayState {
  final SimpleServer httpServer;
  final int port;

  /// The active web download (app -> browser) session, if any.
  final WebSendState? webSendState;

  /// The active web upload (browser -> app) receive session, if any.
  ///
  /// The gateway owns its own receive session so a browser upload never
  /// occupies the native LocalSend receive session.
  final ReceiveSessionState? receiveSession;
  final Map<String, ReceiveSessionState> receiveSessions;

  /// IP address -> attempts. Shared by every web download session on this
  /// gateway listener and only reset when the gateway stops.
  final Map<String, int> pinAttempts;

  /// IP address -> attempts for browser uploads (receive PIN).
  final Map<String, int> receivePinAttempts;

  const WebGatewayState({
    required this.httpServer,
    required this.port,
    required this.webSendState,
    required this.receiveSession,
    this.receiveSessions = const {},
    required this.pinAttempts,
    required this.receivePinAttempts,
  });

  WebGatewayState copyWith({
    SimpleServer? httpServer,
    int? port,
    Object? webSendState = _unset,
    Object? receiveSession = _unset,
    Map<String, ReceiveSessionState>? receiveSessions,
    Map<String, int>? pinAttempts,
    Map<String, int>? receivePinAttempts,
  }) {
    return WebGatewayState(
      httpServer: httpServer ?? this.httpServer,
      port: port ?? this.port,
      webSendState: identical(webSendState, _unset) ? this.webSendState : webSendState as WebSendState?,
      receiveSession: identical(receiveSession, _unset) ? this.receiveSession : receiveSession as ReceiveSessionState?,
      receiveSessions: receiveSessions ?? this.receiveSessions,
      pinAttempts: pinAttempts ?? this.pinAttempts,
      receivePinAttempts: receivePinAttempts ?? this.receivePinAttempts,
    );
  }

  @override
  String toString() {
    return 'WebGatewayState(port: $port, webSendState: $webSendState, '
        'receiveSession: $receiveSession)';
  }
}
