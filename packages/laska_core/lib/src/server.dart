import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app.dart';
import 'db/migrations.dart';
import 'request.dart';
import 'supervisor.dart';

/// Options of the HTTP server.
class ServeOptions {
  /// Creates server options.
  const ServeOptions({
    this.address = '0.0.0.0',
    this.port = 3789,
    this.shared = false,
    this.drainTimeout = const Duration(seconds: 30),
  });

  /// The address the server binds to.
  final String address;

  /// The port the server binds to.
  final int port;

  /// Whether the port may be shared with other processes.
  ///
  /// Worker processes bind the same port with `shared: true`, which is
  /// SO_REUSEPORT on POSIX systems and SO_REUSEADDR on Windows.
  final bool shared;

  /// How long a graceful shutdown waits for in-flight requests.
  final Duration drainTimeout;
}

/// The HTTP server of an application.
///
/// The server keeps track of the requests it is handling, so it can stop
/// accepting new connections, let the running requests finish and only then
/// close the socket.
class LaskaServer {
  /// Creates a server for [app].
  LaskaServer(
    this.app, {
    this.options = const ServeOptions(),
  });

  /// The application being served.
  final Laska app;

  /// The options of the server.
  final ServeOptions options;

  HttpServer? _server;
  int _inFlight = 0;
  bool _closing = false;
  Completer<void>? _drained;

  /// The underlying server, once it is started.
  HttpServer? get server => _server;

  /// The number of requests currently being handled.
  int get inFlight => _inFlight;

  /// Starts listening.
  Future<HttpServer> start() async {
    final server = await HttpServer.bind(
      options.address,
      options.port,
      shared: options.shared,
    );
    _server = server;
    unawaited(
      server.forEach((HttpRequest request) {
        unawaited(_handle(request));
      }),
    );
    return server;
  }

  /// Stops the server.
  ///
  /// The server stops accepting new connections, waits for the running
  /// requests to finish — at most [ServeOptions.drainTimeout] — and closes the
  /// socket afterwards.
  Future<void> stop() async {
    final server = _server;
    if (server == null || _closing) {
      return;
    }
    _closing = true;
    _drained = Completer<void>();
    if (_inFlight == 0) {
      _drained!.complete();
    }

    try {
      await server.close(force: false).timeout(options.drainTimeout);
    } on TimeoutException {
      // The connections did not finish in time, so the socket is closed.
      await server.close(force: true);
    }

    await _drained!.future.timeout(
      options.drainTimeout,
      onTimeout: () {},
    );
    _server = null;
  }

  Future<void> _handle(HttpRequest httpRequest) async {
    _inFlight++;
    try {
      final request = await _readRequest(httpRequest);
      final response = await app.dispatcher.dispatch(request);

      httpRequest.response.statusCode = response.status;
      response.headers.forEach((name, value) {
        httpRequest.response.headers.set(name, value);
      });
      if (response.body.isNotEmpty) {
        httpRequest.response.add(response.body);
      }
      await httpRequest.response.close();
    } catch (_) {
      try {
        httpRequest.response.statusCode = 500;
        await httpRequest.response.close();
      } catch (_) {
        // The client is gone; nothing else can be done.
      }
    } finally {
      _inFlight--;
      if (_closing && _inFlight == 0) {
        _drained?.complete();
      }
    }
  }

  Future<Request> _readRequest(HttpRequest httpRequest) async {
    final body = await utf8.decoder.bind(httpRequest).join();
    final headers = <String, String>{};
    httpRequest.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    return Request(
      method: httpRequest.method.toUpperCase(),
      path: httpRequest.uri.path,
      uri: httpRequest.uri.toString(),
      query: httpRequest.uri.queryParameters,
      headers: headers,
      body: body,
    );
  }
}

/// The flag that makes an application print its route table and exit.
const String routeListFlag = '--laska-route-list';

/// The flag that makes an application apply its migrations and exit.
const String migrateFlag = '--laska-migrate';

/// Starts an HTTP server for [app] and returns it.
///
/// Unlike [run], this does not install signal handlers and does not read the
/// worker environment: it is meant for tests and for embedding a service.
Future<HttpServer> serve(
  Laska app, {
  Object address = '127.0.0.1',
  int port = 0,
  bool shared = false,
}) async {
  final server = LaskaServer(
    app,
    options: ServeOptions(
      address: address is String ? address : address.toString(),
      port: port,
      shared: shared,
    ),
  );
  return server.start();
}

/// Starts an HTTP server for [app] and returns it.
///
/// The server handles SIGINT and, on POSIX systems, SIGTERM: it stops
/// accepting connections, lets the running requests finish and exits.
///
/// The command line arguments of the process are read from [arguments], so a
/// service passes the arguments of its `main` function. The flags of the
/// framework — [routeListFlag] and [migrateFlag] — are handled here.
///
/// When the process was started by the supervisor, the address, the port and
/// the shared socket are taken from the environment.
Future<HttpServer> run(
  Laska app, {
  List<String> arguments = const <String>[],
  Object address = '0.0.0.0',
  int port = 3789,
  bool shared = false,
  Duration drainTimeout = const Duration(seconds: 30),
}) async {
  final flags = <String>[...arguments, ...Platform.executableArguments];

  if (flags.contains(routeListFlag)) {
    stdout.write(app.router.table());
    exit(0);
  }

  if (flags.contains(migrateFlag)) {
    await _migrate(app);
    exit(0);
  }

  final isWorker = Platform.environment[workerEnvironmentKey] == '1';
  final environmentPort =
      int.tryParse(Platform.environment[workerPortEnvironmentKey] ?? '');
  final environmentAddress = Platform.environment[workerAddressEnvironmentKey];

  final server = LaskaServer(
    app,
    options: ServeOptions(
      address: environmentAddress ??
          (address is String ? address : address.toString()),
      port: environmentPort ?? port,
      shared: shared || isWorker,
      drainTimeout: drainTimeout,
    ),
  );

  final httpServer = await server.start();
  _installSignalHandlers(server);

  stdout.writeln(
    '=> Laska listening on http://${httpServer.address.host}:${httpServer.port}',
  );
  return httpServer;
}

void _installSignalHandlers(LaskaServer server) {
  Future<void> handle() async {
    await server.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => handle());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => handle());
  }
}

Future<void> _migrate(Laska app) async {
  final database = app.database;
  if (database == null) {
    stderr.writeln(
      'The application has no database, so there is nothing to migrate.',
    );
    exit(1);
  }

  final directory = Platform.environment['LASKA_MIGRATIONS_DIRECTORY'] ??
      app.migrationsDirectory;
  final runner = MigrationRunner(database, directory: directory);
  final applied = await runner.migrate();

  stdout.writeln('applied ${applied.length} migration(s)');
  for (final migration in applied) {
    stdout.writeln('  ${migration.id}');
  }
}
