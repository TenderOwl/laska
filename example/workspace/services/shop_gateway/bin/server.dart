import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:shop_service/generated/shop.pb.dart';

import 'package:shop_gateway_service/generated/shop_gateway.pb.dart';
import 'package:shop_gateway_service/shop_gateway_service.dart';

Future<void> main(List<String> arguments) async {
  final app = Laska();

  final observability = await Observability.install(
    app,
    logger: Logger(service: 'shop_gateway', version: '0.1.0'),
  );

  // The address of the service that keeps the records. `laska dev` gives it
  // to every service of the workspace.
  final baseUrl = Platform.environment['SHOP_URL'] ?? 'http://127.0.0.1:8080';

  registerShopGatewayService(
    app,
    ShopGatewayServiceImpl(
      shop: ShopServiceClient(
        baseUrl: baseUrl,
        // The tracer of the service joins the trace of the caller, so the two
        // services answer with one trace.
        tracer: observability.tracer,
      ),
    ),
  );

  await run(app, arguments: arguments);
}
