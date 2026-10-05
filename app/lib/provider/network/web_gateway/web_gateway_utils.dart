import 'package:localsend_app/model/state/web_gateway/web_gateway_state.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Same role as [ServerUtils], but bound to the web gateway state so route
/// controllers never need to know about the native server state.
class WebGatewayUtils {
  /// The ref to the provider.
  Ref Function() refFunc;
  Ref get ref => refFunc();

  /// The current gateway state.
  /// This should be used within route controllers because the gateway is
  /// guaranteed to be online and therefore non-null.
  WebGatewayState Function() getState;

  /// The current gateway state or null.
  /// This should be used outside of routes because the gateway may be offline.
  WebGatewayState? Function() getStateOrNull;

  /// Updates the gateway state.
  void Function(WebGatewayState? Function(WebGatewayState? oldState) builder) setState;

  WebGatewayUtils({
    required this.refFunc,
    required this.getState,
    required this.getStateOrNull,
    required this.setState,
  });
}
