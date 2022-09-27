import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:event/event.dart';
import 'package:laska/src/events.dart';

import 'package:laska/src/middleware/middleware.dart';
import 'package:laska/src/router.dart';
import 'package:laska/src/server.dart';
import 'package:laska/src/config.dart';

class Laska {
  Configuration? config;

  var before_startup = Event<StartupEventArgs>();
  var after_startup = Event<StartupEventArgs>();
  var before_teardown = Event<TeardownEventArgs>();
  var after_teardown = Event<TeardownEventArgs>();

  Laska(
      {this.config,
      String address = '0.0.0.0',
      int port = 3789,
      int? isolateCount,
      Router? router}) {
    // Init configuration
    config ??= Configuration()
      ..address
      ..port
      ..isolatesCount = isolateCount ?? Platform.numberOfProcessors
      ..middlewares = <Middleware>{}
      ..router = router ?? Router();
  }

  // API to user laska.router object
  Router get router => config!.router!;

  set router(Router router) => config!.router = router;

  /// Registers a new GET route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void GET(String path, Function handler, {Set<Middleware>? middlewares}) {
    any('GET', path, handler, middlewares: middlewares);
  }

  /// Registers a new POST route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void POST(String path, Function handler, {Set<Middleware>? middlewares}) {
    any('POST', path, handler, middlewares: middlewares);
  }

  /// Registers a new PUT route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void PUT(String path, Function handler, {Set<Middleware>? middlewares}) {
    any('PUT', path, handler, middlewares: middlewares);
  }

  /// Registers a new DELETE route for a `path` with matching `handler` in the router
  /// with optional route-level `middlewares`.
  void DELETE(String path, Function handler, {Set<Middleware>? middlewares}) {
    any('DELETE', path, handler, middlewares: middlewares);
  }

  // Registers a new route for all HTTP methods and `path` with matching `handler`
  // in the router with optional route-level `middlewares`.
  void any(String method, String path, Function handler,
      {Set<Middleware>? middlewares}) {
    config!.router!.insert(method, path, handler, middlewares: middlewares);
  }

  // Attach middleware to request processing pipeline
  void Use(Middleware middleware) {
    if (!config!.middlewares!.contains(middleware)) {
      config!.middlewares?.add(middleware);
    }
  }
}

Future run(Laska app) async {
  app.before_startup.broadcast(StartupEventArgs(app));

  // Store out workers
  var workers = <Worker>[];

  for (var i = 0; i < app.config!.isolatesCount - 1; i++) {
    // Init worker and store its communication ports
    var receiverPort = ReceivePort();
    var iso = await Isolate.spawn(_startServer, receiverPort.sendPort);
    var sendPort = await receiverPort.first;

    sendPort.send(app);
    workers.add(Worker(iso, receiverPort, sendPort));
  }

  var receivePort = ReceivePort();
  await _startServer(receivePort.sendPort);
  var sendPort = (await receivePort.first as SendPort);
  sendPort.send(app);

  app.after_startup.broadcast(StartupEventArgs(app));

  print('=> http server started on '
      '${app.config!.address}:${app.config!.port}');
}

Future _startServer(SendPort sendPort) async {
  var receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  var server;
  receivePort.listen((message) async {
    // If we've got a message with configuration
    // then start a server to listen connections
    if (message is Laska) {
      server = Server(message.config!);
      await server.run();
    }
  });
}
