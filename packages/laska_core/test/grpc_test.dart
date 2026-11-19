import 'package:grpc/grpc.dart' as grpc;
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// Registers a service that answers with the bytes it received.
void _register(
  Laska app, {
  GrpcHandler? handler,
  List<Middleware> middleware = const <Middleware>[],
}) {
  app.grpc.add(
    GrpcService(
      name: 'users.v1.UsersService',
      methods: <String, GrpcHandler>{
        'GetUser': handler ?? (bytes) async => bytes,
      },
      middleware: middleware,
    ),
  );
}

/// Calls the method [method] of the service and answers with the error of the
/// call, if the call fails.
Future<grpc.GrpcError> _fail(
  GrpcServer server,
  String method,
  List<int> body,
) =>
    _failPath(server, '/users.v1.UsersService/$method', body);

/// Calls a method of a service the server does not know and answers with the
/// error of the call.
Future<grpc.GrpcError> _failService(GrpcServer server, String service) =>
    _failPath(server, '/$service/GetUser', const <int>[]);

/// Calls the method at [path] and answers with the error of the call, if the
/// call fails.
Future<grpc.GrpcError> _failPath(
  GrpcServer server,
  String path,
  List<int> body,
) async {
  final channel = grpc.ClientChannel(
    '127.0.0.1',
    port: server.port,
    options: const grpc.ChannelOptions(
      credentials: grpc.ChannelCredentials.insecure(),
    ),
  );
  addTearDown(channel.shutdown);

  final call = channel.createCall<List<int>, List<int>>(
    grpc.ClientMethod<List<int>, List<int>>(
      path,
      (List<int> value) => value,
      (List<int> value) => value,
    ),
    Stream<List<int>>.value(body),
    grpc.CallOptions(),
  );

  try {
    await call.response.single;
  } on grpc.GrpcError catch (error) {
    // The client closes the stream of the call in the background, and
    // package:http2 asserts that a connection does not end with an open
    // stream. The channel is closed after the cleanup.
    await Future<void>.delayed(grpcSettleDelay);
    return error;
  }
  fail('The call was expected to fail.');
}

void main() {
  group('the gRPC server', () {
    late Laska app;
    late GrpcServer server;

    setUp(() async {
      app = Laska();
      server = GrpcServer(app, address: '127.0.0.1', port: 0);
    });

    tearDown(() async {
      await server.stop();
    });

    test('answers a call with the bytes of the handler', () async {
      _register(app);
      await server.start();

      final transport = GrpcServiceTransport(
        host: '127.0.0.1',
        port: server.port,
      );
      addTearDown(transport.close);

      final response = await transport.send(
        TransportRequest(
          method: 'POST',
          uri: transport.buildUri(
            '/v1/users/u_1',
            '/users.v1.UsersService/GetUser',
          ),
          body: <int>[1, 2, 3],
        ),
      );

      expect(response.statusCode, 200);
      expect(response.body, <int>[1, 2, 3]);
    });

    test('serves the service under the name of the contract', () async {
      _register(app);
      await server.start();

      expect(server.services.single.name, 'users.v1.UsersService');
    });

    test('runs the middleware of the application before the method', () async {
      final paths = <String>[];
      app.use((request, next) async {
        paths.add(request.path);
        return next();
      });
      _register(app);
      await server.start();

      final transport = GrpcServiceTransport(
        host: '127.0.0.1',
        port: server.port,
      );
      addTearDown(transport.close);

      await transport.send(
        TransportRequest(
          method: 'POST',
          uri: transport.buildUri(
            '/v1/users/u_1',
            '/users.v1.UsersService/GetUser',
          ),
          body: const <int>[],
        ),
      );

      expect(paths, <String>['/users.v1.UsersService/GetUser']);
    });

    test('gives the metadata of the call to the middleware', () async {
      final headers = <String, String>{};
      app.use((request, next) async {
        headers.addAll(request.headers);
        return next();
      });
      _register(app);
      await server.start();

      final transport = GrpcServiceTransport(
        host: '127.0.0.1',
        port: server.port,
        metadata: <String, String>{'authorization': 'Bearer token'},
      );
      addTearDown(transport.close);

      await transport.send(
        TransportRequest(
          method: 'POST',
          uri: transport.buildUri(
            '/v1/users/u_1',
            '/users.v1.UsersService/GetUser',
          ),
          body: const <int>[],
        ),
      );

      expect(headers['authorization'], 'Bearer token');
    });

    test('answers with the status of the error of the service', () async {
      _register(
        app,
        handler: (bytes) async => throw HttpException(
          404,
          'User "u_1" was not found',
          code: 'user_not_found',
        ),
      );
      await server.start();

      final error = await _fail(server, 'GetUser', const <int>[]);

      expect(error.code, GrpcStatus.notFound);
      expect(error.message, 'User "u_1" was not found');
    });

    test('answers with the status of the middleware that stops the call',
        () async {
      app.use((request, next) async => Response(status: 401));
      _register(app);
      await server.start();

      final error = await _fail(server, 'GetUser', const <int>[]);

      expect(error.code, GrpcStatus.unauthenticated);
    });

    test('answers with an internal error when the service fails', () async {
      _register(
        app,
        handler: (bytes) async => throw StateError('the database is down'),
      );
      await server.start();

      final error = await _fail(server, 'GetUser', const <int>[]);

      expect(error.code, GrpcStatus.internal);
    });

    test('keeps the status of a failure of a dependency', () async {
      _register(
        app,
        handler: (bytes) async => throw DependencyTimeoutException(
          'users',
          const Duration(seconds: 2),
        ),
      );
      await server.start();

      final error = await _fail(server, 'GetUser', const <int>[]);

      expect(error.code, GrpcStatus.deadlineExceeded);
    });

    test('answers with an unimplemented error for an unknown method', () async {
      _register(app);
      await server.start();

      final error = await _fail(server, 'DeleteUser', const <int>[]);

      expect(error.code, GrpcStatus.unimplemented);
    });

    test('closes the connection after a call of an unknown method', () async {
      _register(app);
      await server.start();

      final error = await _fail(server, 'DeleteUser', const <int>[]);
      expect(error.code, GrpcStatus.unimplemented);

      // The server closes the connection while the client is still there. The
      // stream of the call is closed the way every other stream is, so the
      // connection does not end with an open stream.
      await server.stop().timeout(const Duration(seconds: 5));
    });

    test('answers with an unimplemented error for an unknown service',
        () async {
      _register(app);
      await server.start();

      final error = await _failService(server, 'orders.v1.OrdersService');
      expect(error.code, GrpcStatus.unimplemented);

      await server.stop().timeout(const Duration(seconds: 5));
    });

    test('serves the service registered on a group', () async {
      app.group('/v1', (group) {
        _register(group);
      });
      await server.start();

      final transport = GrpcServiceTransport(
        host: '127.0.0.1',
        port: server.port,
      );
      addTearDown(transport.close);

      final response = await transport.send(
        TransportRequest(
          method: 'POST',
          uri: transport.buildUri(
            '/v1/users/u_1',
            '/users.v1.UsersService/GetUser',
          ),
          body: <int>[7],
        ),
      );

      expect(response.body, <int>[7]);
    });

    test('runs the middleware of the group of the service', () async {
      final paths = <String>[];
      app.group('/v1', (group) {
        group.use((request, next) async {
          paths.add(request.path);
          return next();
        });
        _register(group);
      });
      await server.start();

      final transport = GrpcServiceTransport(
        host: '127.0.0.1',
        port: server.port,
      );
      addTearDown(transport.close);

      await transport.send(
        TransportRequest(
          method: 'POST',
          uri: transport.buildUri(
            '/v1/users/u_1',
            '/users.v1.UsersService/GetUser',
          ),
          body: const <int>[],
        ),
      );

      expect(paths, <String>['/users.v1.UsersService/GetUser']);
    });

    test('stops the server', () async {
      _register(app);
      await server.start();

      expect(server.isRunning, isTrue);

      await server.stop();

      expect(server.isRunning, isFalse);
    });
  });

  group('serveGrpc', () {
    test('starts a server for the services of the application', () async {
      final app = Laska();
      _register(app);

      final server = await serveGrpc(app, address: '127.0.0.1', port: 0);
      addTearDown(server.stop);

      expect(server.port, isNotNull);
      expect(server.services, hasLength(1));
    });
  });
}
