import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:laska/src/context.dart';
import 'package:laska/src/middleware/middleware.dart';
import 'package:laska/src/router.dart';
import 'package:laska/src/config.dart';

class Worker {
  Isolate isolate;
  ReceivePort receivePort;
  SendPort sendPort;

  Worker(this.isolate, this.receivePort, this.sendPort);
}

/// Laska server class.
///
/// This class is responsible for starting the server and handling the requests.
///
/// It also handles the worker pool.
/// It is also responsible for handling the configuration.
/// It is also responsible for handling the middleware.
/// It is also responsible for handling the router.
/// It is also responsible for handling the context.
/// It is also responsible for handling the error handling.
/// It is also responsible for handling the request handling.
/// It is also responsible for handling the response handling.
///
/// Thank you GitHub Copilot for the inspiration! :D
class Server {
  Configuration config;
  HttpServer? server;
  Router? router;
  Set<Middleware>? middlewares;

  /// Initializes the server with the [Configuration].
  Server(this.config) {
    router = config.router;
    middlewares = config.middlewares;
  }

  /// Starts the server.
  ///
  /// This method will try to bind the [Configuration.address] and
  /// [Configuration.port] to the server and start to listen for incoming
  /// requests.
  Future run() async {
    server = await HttpServer.bind(config.address, config.port, shared: true);
    server!.listen(handleRequest);
    log('=> worker [PID:${identityHashCode(this)}] is ready');
  }

  /// Handles the incoming request.
  ///
  /// This method will try to find a route for the incoming request.
  Future handleRequest(HttpRequest request) async {
    var context = Context(request, route: null);

    var route = router?.lookup(request.uri.path);

    // Check if route has a handler
    if (route == null) {
      await sendNotFound(context);
    } else {
      var handler = route.handlers[request.method];
      var routeMiddlewares = route.middlewares![request.method];
      // Check if route use the same method as requested=
      if (handler == null) {
        await sendMethodNotAllowed(context);
      } else {
        try {
          context.route = route;

          // Concatenate global and route middlewares
          handler =
              await _applyMiddlewares(handler, context, routeMiddlewares ?? {});

          // Apply middlewares
          handler =
              await _applyMiddlewares(handler, context, middlewares ?? {});

          // If the handler still not null we can safely call it.
          await handler(context);
        } catch (exception) {
          // TODO: no prints! in production code
          // log(exception.toString());
          log(exception.toString());
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
        handler = await middleware.execute(handler, context);
      }
    }
    return handler;
  }

  Future sendInternalError(Context context) async {
    context.response!.statusCode = HttpStatus.internalServerError;
    await context.Text('Internal Server Error',
        statusCode: HttpStatus.internalServerError);
  }

  Future sendNotFound(Context context) async {
    await context.Text('Not Found', statusCode: HttpStatus.notFound);
  }

  Future sendMethodNotAllowed(Context context) async {
    await context.Text('Method Not Allowed',
        statusCode: HttpStatus.methodNotAllowed);
  }
}
