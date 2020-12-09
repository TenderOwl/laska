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
      if (route['node']?.handler != null) {
        Function.apply(route['node'].handler, [request], route['params']);
      } else {
        request.response.write('Not Found');
      }

      await request.response.close();
    }
  }

  void GET(String path, Function handler) {
    router.insert('GET', path, handler);
  }

  void POST(String path, Function handler) {
    router.insert('POST', path, handler);
  }
}
