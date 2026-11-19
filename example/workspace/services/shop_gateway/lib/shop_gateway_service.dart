import 'package:laska_core/laska_core.dart';
import 'package:shop_service/generated/shop.pb.dart';

import 'generated/shop_gateway.pb.dart';

/// The implementation of the ShopGatewayService service.
class ShopGatewayServiceImpl implements ShopGatewayService {
  ShopGatewayServiceImpl({required this.shop});

  /// The client of the service that keeps the records.
  final ShopServiceClient shop;

  @override
  Future<ShopView> getShopView(GetShopViewRequest request) async {
    final Shop record;
    try {
      record = await shop.getShop(
        GetShopRequest(id: request.id),
      );
    } on LaskaApiException catch (error) {
      // The status of the service behind becomes the status of this service,
      // so the caller sees what really happened.
      throw HttpException(
        error.statusCode,
        error.statusCode == 404
            ? 'The record "${request.id}" was not found'
            : 'The service behind is not available',
        code: error.statusCode == 404 ? 'not_found' : 'dependency_error',
      );
    }
    return ShopView(id: record.id, name: record.name);
  }
}
