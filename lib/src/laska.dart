import 'dart:io';

import 'package:event/event.dart';
import 'package:laska/src/events.dart';

import 'middleware/middleware.dart';
import 'router.dart';
import 'server.dart';
import 'config.dart';

class Laska {
  Configuration config;

  var before_startup = Event<StartupEventArgs>();
  var after_startup = Event<StartupEventArgs>();
  var before_teardown = Event<TeardownEventArgs>();
  var after_teardown = Event<TeardownEventArgs>();

  Server server;

  Laska(
      {this.config,
      String address = '0.0.0.0',
      int port = 3789,
      Router router}) {
    // Init configuration
    config ??= Configuration()
      ..address = address ?? 'localhost'
      ..port = port ?? 3788
      ..middlewares = <Middleware>{}
      ..router = router ?? Router();
  }

  // API to user laska.router object
  Router get router => config.router;

  set router(Router router) => config.router = router;

  /// Registers a new GET route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void GET(String path, Function handler, {Set<Middleware> middlewares}) {
    any('GET', path, handler, middlewares: middlewares);
  }

  /// Registers a new PATCH route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void PATCH(String path, Function handler, {Set<Middleware> middlewares}) {
    any('PATCH', path, handler, middlewares: middlewares);
  }

  /// Registers a new POST route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void POST(String path, Function handler, {Set<Middleware> middlewares}) {
    any('POST', path, handler, middlewares: middlewares);
  }

  /// Registers a new PUT route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void PUT(String path, Function handler, {Set<Middleware> middlewares}) {
    any('PUT', path, handler, middlewares: middlewares);
  }

  /// Registers a new DELETE route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void DELETE(String path, Function handler, {Set<Middleware> middlewares}) {
    any('DELETE', path, handler, middlewares: middlewares);
  }

  // Registers a new route for all HTTP methods and `path` with matching `handler`
  // in the router with optional route-level `middlewares`.
  void any(String method, String path, Function handler,
      {Set<Middleware> middlewares}) {
    config.router.insert(method, path, handler, middlewares: middlewares);
  }

  void Use(Middleware middleware) {
    if (!config.middlewares.contains(middleware)) {
      config.middlewares.add(middleware);
    }
  }

  void run() async {
    await before_startup.broadcast(StartupEventArgs(this));

    server = Server(config, app: this);
    await server.run();

    await after_startup.broadcast(StartupEventArgs(this));

    // Listen for SIGKILL and SIGINT to perform graceful teardown.
    ProcessSignal.sigint.watch().listen((event) async => await stop());
    ProcessSignal.sigterm.watch().listen((event) async => await stop());
  }

  void stop({bool force = false}) async {
    print('\nStopping server...');

    await before_teardown.broadcast(TeardownEventArgs(this));
    await server.stop(force: force);
    await after_teardown.broadcast(TeardownEventArgs(this));

    exit(0);
  }
}

// Future<void> run(Laska app) async {
//   // config.router = router;
//
//   // Store out workers
//   var workers = <Worker>[];
//
//   for (var i = 0; i < app.config.isolatesCount - 1; i++) {
//     // Init worker and store its communication ports
//     var receiverPort = ReceivePort();
//     var iso = await Isolate.spawn(_startServer, receiverPort.sendPort);
//     var sendPort = await receiverPort.first;
//
//     sendPort.send(app);
//     workers.add(Worker()
//       ..receivePort = receiverPort
//       ..sendPort = sendPort
//       ..isolate = iso);
//   }
//
//   var receivePort = ReceivePort();
//   await _startServer(receivePort.sendPort);
//   var sendPort = (await receivePort.first as SendPort);
//   sendPort.send(app);
//
//   print('=> http server started on '
//       '${app.config.address}:${app.config.port}');
// }
//
// void _startServer(SendPort sendPort) async {
//   var receivePort = ReceivePort();
//   sendPort.send(receivePort.sendPort);
//
//   var server;
//   receivePort.listen((message) async {
//     // If we've got a message with configuration
//     // then start a server to listen connections
//     if (message is Laska) {
//       server = Server(message.config);
//       await server.run();
//     }
//   });
// }
