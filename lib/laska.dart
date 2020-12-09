import 'dart:io';

import 'package:laska/router.dart';

class Laska {
  String address;
  final int port;
  var router = Router();

  Laska({this.address = '0.0.0.0', this.port = 3789});

  void run() async {
    final server = await createServer();
    print('Server started: ${server.address} port ${server.port}');
    await handleRequest(server);
  }

  Future<HttpServer> createServer() async {
    // final address = InternetAddress.loopbackIPv4;
    return await HttpServer.bind(address, port);
  }

  void handleRequest(HttpServer server) async {
    await for (HttpRequest request in server) {
      var route = router.lookup(request.uri.path);

      if (route?.handler != null) {
        try {
          Function.apply(route.handler, [request], route.params);
        } catch (exception) {
          print('EXCEPTION: $exception');
          await sendInternalError(request.response);
        }
      } else {
        await sendNotFound(request.response);
      }

      await request.response.close();
    }
  }

  void sendInternalError(HttpResponse response) async {
    response.statusCode = HttpStatus.internalServerError;
    await response.close();
  }

  void sendNotFound(HttpResponse response) async {
    response.statusCode = HttpStatus.notFound;
    response.write('Not Found');
    await response.close();
  }

  void GET(String path, Function handler) {
    router.insert('GET', path, handler);
  }

  void POST(String path, Function handler) {
    router.insert('POST', path, handler);
  }
}
