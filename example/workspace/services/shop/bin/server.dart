import 'package:laska_core/laska_core.dart';

import 'package:shop_service/generated/shop.pb.dart';
import 'package:shop_service/shop_service.dart';

Future<void> main(List<String> arguments) async {
  final app = Laska();

  await Observability.install(
    app,
    logger: Logger(service: 'shop', version: '0.1.0'),
  );

  registerShopService(app, ShopServiceImpl());

  await run(app, arguments: arguments);
}
