import 'package:grpc/grpc.dart' as grpc;
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// A gRPC service that answers with the bytes it received.
class _EchoService extends grpc.Service {
  @override
  String get $name => 'users.v1.UsersService';

  /// How many calls the service received.
  int calls = 0;

  _EchoService() {
    $addMethod(
      grpc.ServiceMethod<List<int>, List<int>>(
        'GetUser',
        (grpc.ServiceCall call, Future<List<int>> request) async {
          calls++;
          final bytes = await request;
          return bytes;
        },
        false,
        false,
        (List<int> value) => value,
        (List<int> value) => value,
      ),
    );
  }
}

void main() {
  group('the gRPC transport', () {
    late grpc.Server server;
    late _EchoService service;

    setUp(() async {
      service = _EchoService();
      server = grpc.Server.create(services: <grpc.Service>[service]);
      await server.serve(address: '127.0.0.1', port: 0);
    });

    tearDown(() async {
      await server.shutdown();
    });

    test('talks to a gRPC service', () async {
      final transport = GrpcServiceTransport(
        host: '127.0.0.1',
        port: server.port!,
      );

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
      expect(service.calls, 1);

      await transport.close();
    });

    test('builds the address of the method of the contract', () {
      final transport = GrpcServiceTransport(host: 'localhost', port: 50051);

      expect(
        transport
            .buildUri('/v1/users/u_1', '/users.v1.UsersService/GetUser')
            .toString(),
        'http://localhost:50051/users.v1.UsersService/GetUser',
      );
    });

    test('speaks the binary format of the contract', () {
      final transport = GrpcServiceTransport(host: 'localhost');

      expect(transport.bodyFormat, BodyFormat.protobuf);
    });
  });

  group('the HTTP transport', () {
    test('speaks the JSON format of the contract', () {
      final transport = HttpServiceTransport(baseUrl: 'http://localhost:8080');

      expect(transport.bodyFormat, BodyFormat.json);
    });

    test('builds the address of the REST path', () {
      final transport = HttpServiceTransport(baseUrl: 'http://localhost:8080');

      expect(
        transport
            .buildUri('/v1/users/u_1', '/users.v1.UsersService/GetUser')
            .toString(),
        'http://localhost:8080/v1/users/u_1',
      );
    });
  });
}
