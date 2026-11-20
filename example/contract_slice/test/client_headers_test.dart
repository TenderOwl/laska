import 'dart:io';

import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:contract_slice_example/service.dart';
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// The middleware that only lets the calls of the caller through.
///
/// It stands for the middleware of the authentication of a service: it reads
/// the token of the session out of the headers of the call.
Middleware _onlyTheCaller(String token) => (request, next) async {
      if (request.header('authorization') != token) {
        return Response.problem(
          401,
          'Unauthorized',
          'The token of the caller is required.',
        );
      }
      return next();
    };

void main() {
  group('the headers of the call', () {
    late Laska app;
    late HttpServer httpServer;
    late GrpcServer grpcServer;
    late UsersServiceClient httpClient;
    late UsersServiceClient grpcClient;
    late GrpcServiceTransport transport;

    setUp(() async {
      app = Laska();
      app.use(_onlyTheCaller('Bearer the-token'));
      registerUsersService(app, UsersServiceImpl());

      httpServer = await serve(app, address: '127.0.0.1', port: 0);
      grpcServer = await serveGrpc(app, address: '127.0.0.1', port: 0);

      httpClient = UsersServiceClient(
        baseUrl: 'http://127.0.0.1:${httpServer.port}',
      );
      transport = GrpcServiceTransport(
        host: '127.0.0.1',
        port: grpcServer.port,
      );
      grpcClient = UsersServiceClient(
        baseUrl: 'http://127.0.0.1:${grpcServer.port}',
        transport: transport,
      );
    });

    tearDown(() async {
      await transport.close();
      await grpcServer.stop();
      await httpServer.close(force: true);
    });

    test('the caller passes the token of the session over HTTP', () async {
      final user = await httpClient.getUser(
        const GetUserRequest(id: 'u_1'),
        headers: const <String, String>{
          'authorization': 'Bearer the-token',
        },
      );

      expect(user.id, 'u_1');
    });

    test('a call without the token is refused over HTTP', () async {
      await expectLater(
        httpClient.getUser(const GetUserRequest(id: 'u_1')),
        throwsA(
          isA<LaskaApiException>()
              .having((error) => error.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('the caller passes the token of the session over gRPC', () async {
      final user = await grpcClient.getUser(
        const GetUserRequest(id: 'u_1'),
        headers: const <String, String>{
          'authorization': 'Bearer the-token',
        },
      );

      expect(user.id, 'u_1');
    });

    test('a call without the token is refused over gRPC', () async {
      await expectLater(
        grpcClient.getUser(const GetUserRequest(id: 'u_1')),
        throwsA(
          isA<LaskaApiException>()
              .having((error) => error.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('the headers of the caller do not break the call', () async {
      final user = await httpClient.getUser(
        const GetUserRequest(id: 'u_1'),
        headers: const <String, String>{
          'authorization': 'Bearer the-token',
          'x-request-id': 'the-id-of-the-call',
          'accept-language': 'ru',
        },
      );

      expect(user.id, 'u_1');
    });
  });
}
