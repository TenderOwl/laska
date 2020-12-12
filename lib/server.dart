import 'dart:io';
import 'dart:isolate';

import 'config.dart';

class Worker {
  Isolate isolate;
  ReceivePort receivePort;
  SendPort sendPort;
}

class Server {
  Configuration config;
  var server;
  var router;

  Server(this.config) {
    router = config.router;
  }

  void run() async {
    server = await HttpServer.bind(config.address, config.port, shared: true);
    server.listen(handleRequest);
    print('=> worker [PID:${identityHashCode(this)}] is ready');
  }

  void handleRequest(HttpRequest request) async {
    var route = router.lookup(request.uri.path);

    if (route?.handler != null) {
      try {
        request.response.headers.contentType = ContentType.html;
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

  void sendInternalError(HttpResponse response) async {
    response.statusCode = HttpStatus.internalServerError;
    await response.close();
  }

  void sendNotFound(HttpResponse response) async {
    response.statusCode = HttpStatus.notFound;
    response.write('Not Found');
    await response.close();
  }
}
