import 'dart:io';
import 'dart:isolate';

import 'context.dart';
import 'middleware/middleware.dart';
import 'router.dart';

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
  Set<Middleware> middlewares;

  Server(this.config) {
    router = config.router;
    middlewares = config.middlewares;
  }

  void run() async {
    server = await HttpServer.bind(config.address, config.port);
    server.listen(handleRequest);
    print('Server started on http://${config.address}:${config.port}');
  }

  void handleRequest(HttpRequest request) async {
    var context = Context(request);

    var route = router.lookup(request.uri.path);

    // Check if route has a handler
    if (route == null || route.handlers == null) {
      await sendNotFound(context);
    } else {
      var handler = route.handlers[request.method];
      var routeMiddlewares = route.middlewares[request.method];
      // Check if route use the same method as requested=
      if (handler == null) {
        await sendMethodNotAllowed(context);
      } else {
        try {
          context.route = route;

          // Concatenate global and route middlewares
          handler = await _applyMiddlewares(handler, context, routeMiddlewares ?? {});

          // Apply middlewares
          handler = await _applyMiddlewares(handler, context, middlewares);

          // If the handler still not null we can safely call it.
          if (handler != null) {
            await handler(context);
          }
        } catch (exception) {
          // TODO: no prints! in production code
          print(exception);
          await sendInternalError(context);
        }
      }
    }

    await request.response.close();
  }

  Future<Function> _applyMiddlewares(
      Function handler, Context context, Set<Middleware> middlewares) async {
    // Iterate over global middlewares and execute them one after another
    if (middlewares.isNotEmpty) {
      for (var middleware in middlewares.toList().reversed) {
        // Middleware can return [null] in case
        // if it's need to stop request handling.
        if (handler != null) {
          handler = await middleware.execute(handler, context);
        } else {
          break;
        }
      }
    }
    return handler;
  }

  void sendInternalError(Context context) async {
    context.response.statusCode = HttpStatus.internalServerError;
    await context.Text('Internal Server Error',
        statusCode: HttpStatus.internalServerError);
  }

  void sendNotFound(Context context) async {
    await context.Text('Not Found', statusCode: HttpStatus.notFound);
  }

  void sendMethodNotAllowed(Context context) async {
    await context.Text('Method Not Allowed',
        statusCode: HttpStatus.methodNotAllowed);
  }
}
