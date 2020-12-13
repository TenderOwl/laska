import 'dart:io';
import 'dart:isolate';

import 'package:laska/context.dart';
import 'package:laska/router.dart';

import 'config.dart';

class Worker {
  Isolate isolate;
  ReceivePort receivePort;
  SendPort sendPort;
}

class Server {
  Configuration config;
  HttpServer server;
  Router router;

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

    var context = Context(request);

    if (route?.handler != null) {
      try {
        context.route = route;
        Function.apply(route.handler, [context]);
      } catch (exception) {
        print('EXCEPTION: $exception');
        await sendInternalError(context);
      }
    } else {
      await sendNotFound(context);
    }

    await request.response.close();
  }

  void sendInternalError(Context context) async {
    context.response.statusCode = HttpStatus.internalServerError;
    await context.Text('Internal Server Error',
        statusCode: HttpStatus.internalServerError);
  }

  void sendNotFound(Context context) async {
    await context.Text('Not Found', statusCode: HttpStatus.notFound);
  }
}
