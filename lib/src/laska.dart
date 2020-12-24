import 'dart:io';
import 'dart:isolate';

import 'middleware/middleware.dart';
import 'router.dart';
import 'server.dart';
import 'config.dart';

class Laska {
  Configuration config;

  Laska(
      {this.config,
      String address = '0.0.0.0',
      int port = 3789,
      int isolateCount,
      Router router}) {
    // Init configuration
    config ??= Configuration()
      ..address = address ?? 'localhost'
      ..port = port ?? 3788
      ..isolatesCount = isolateCount ?? Platform.numberOfProcessors
      ..middleware = <Middleware>[]
      ..router = router ?? Router();
  }

  // API to user laska.router object
  Router get router => config.router;

  set router(Router router) => config.router = router;

  void GET(String path, Function handler) {
    handle('GET', path, handler);
  }

  void POST(String path, Function handler) {
    handle('POST', path, handler);
  }

  void PUT(String path, Function handler) {
    handle('PUT', path, handler);
  }

  void DELETE(String path, Function handler) {
    handle('DELETE', path, handler);
  }

  void handle(String method, String path, Function handler) {
    config.router.insert(method, path, handler);
  }

  void Use(Middleware middleware) {
    if (!config.middleware.contains(middleware)) {
      config.middleware.add(middleware);
    }
  }
}

Future<void> run(Laska app) async {
  // config.router = router;

  // Store out workers
  var workers = <Worker>[];

  for (var i = 0; i < app.config.isolatesCount - 1; i++) {
    // Init worker and store its communication ports
    var receiverPort = ReceivePort();
    var iso = await Isolate.spawn(_startServer, receiverPort.sendPort);
    var sendPort = await receiverPort.first;

    sendPort.send(app);
    workers.add(Worker()
      ..receivePort = receiverPort
      ..sendPort = sendPort
      ..isolate = iso);
  }

  var receivePort = ReceivePort();
  await _startServer(receivePort.sendPort);
  var sendPort = (await receivePort.first as SendPort);
  sendPort.send(app);

  print('=> http server started on '
      '${app.config.address}:${app.config.port}');
}

void _startServer(SendPort sendPort) async {
  var receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  var server;
  receivePort.listen((message) async {
    // If we've got a message with configuration
    // then start a server to listen connections
    if (message is Laska) {
      server = Server(message.config);
      await server.run();
    }
  });
}
