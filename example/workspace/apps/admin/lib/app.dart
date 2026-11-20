import 'dart:async';
import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:shop_gateway_service/generated/shop_gateway.pb.dart';

/// The key of the zone that holds the request of the caller.
const Object _caller = 'laska.app.caller';

/// Registers the routes of the app.
///
/// The app serves the frontend of the workspace and calls the services behind
/// it, so the browser of the user talks to the app and not to the services.
///
/// The clients of the services may be given, so a test answers the calls of
/// the app without opening a socket.
void registerApp(Laska app, {ShopGatewayServiceClient? shopGateway}) {
  // The request of the caller is kept in the zone of the call, so the proxy
  // of a service can pass the headers of the caller with the call.
  app.use(_keepTheCaller());

  // The frontend of the workspace. The build of the frontend belongs to the
  // application: put the result of it in the directory of the files.
  final files = Platform.environment['LASKA_WEB_ROOT'] ?? 'web';
  app.staticFiles('/', files, fallback: 'index.html');

  // The service "shop_gateway" behind the app.
  final shopGatewayClient = shopGateway ??
      ShopGatewayServiceClient(
        baseUrl:
            Platform.environment['SHOP_GATEWAY_URL'] ?? 'http://127.0.0.1:8081',
      );
  registerShopGatewayService(
    app,
    ShopGatewayProxy(shopGatewayClient),
    grpc: false,
  );
}

/// The proxy of the "shop_gateway" service.
///
/// The proxy forwards the call of the frontend to the service behind it and
/// passes the headers of the caller with it, so the token of the session of
/// the browser reaches the service.
class ShopGatewayProxy implements ShopGatewayService {
  /// Creates the proxy of the service behind.
  ShopGatewayProxy(this._client);

  /// The client of the service behind.
  final ShopGatewayServiceClient _client;

  @override
  Future<ShopView> getShopView(GetShopViewRequest request) =>
      _client.getShopView(request, headers: _headersOfTheCaller());
}

/// The headers of the caller, e.g. the token of the session.
Map<String, String> _headersOfTheCaller() {
  final request = Zone.current[_caller];
  if (request is! Request) {
    return const <String, String>{};
  }
  final token = request.header('authorization');
  if (token == null) {
    return const <String, String>{};
  }
  return <String, String>{'authorization': token};
}

/// The middleware that keeps the request of the caller.
Middleware _keepTheCaller() => (request, next) {
      return runZoned(
        () => next(),
        zoneValues: <Object, Object?>{_caller: request},
      );
    };
