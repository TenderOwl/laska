import 'dart:io';

import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:contract_slice_example/service.dart';
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('the gRPC projection of the contract', () {
    late Laska app;
    late GrpcServer grpcServer;
    late HttpServer httpServer;
    late UsersServiceClient grpcClient;
    late UsersServiceClient httpClient;

    setUp(() async {
      app = Laska();
      registerUsersService(app, UsersServiceImpl());

      grpcServer = await serveGrpc(app, address: '127.0.0.1', port: 0);
      httpServer = await serve(app, address: '127.0.0.1', port: 0);

      grpcClient = UsersServiceClient(
        baseUrl: 'http://127.0.0.1:${grpcServer.port}',
        transport: GrpcServiceTransport(
          host: '127.0.0.1',
          port: grpcServer.port,
        ),
      );
      httpClient = UsersServiceClient(
        baseUrl: 'http://127.0.0.1:${httpServer.port}',
      );
    });

    tearDown(() async {
      await grpcServer.stop();
      await httpServer.close(force: true);
    });

    test('the generated client talks to the service over gRPC', () async {
      final user = await grpcClient.getUser(const GetUserRequest(id: 'u_1'));

      expect(user.id, 'u_1');
      expect(user.email, 'ada@example.com');
      expect(user.displayName, 'Ada Lovelace');
      expect(user.role, UserRole.userRoleAdmin);
      expect(user.tags, <String>['founder', 'mathematician']);
      expect(user.createdAt.toJson(), '2026-01-01T00:00:00Z');
    });

    test('the answer is the same as the one over HTTP', () async {
      const request = GetUserRequest(id: 'u_1');

      final overGrpc = await grpcClient.getUser(request);
      final overHttp = await httpClient.getUser(request);

      expect(overGrpc.id, overHttp.id);
      expect(overGrpc.email, overHttp.email);
      expect(overGrpc.role, overHttp.role);
      expect(overGrpc.createdAt.toJson(), overHttp.createdAt.toJson());
    });

    test('a page of users is a page over gRPC as well', () async {
      final response = await grpcClient.listUsers(
        const ListUsersRequest(limit: 1, cursor: ''),
      );

      expect(response.users, hasLength(1));
      expect(response.users.first.id, 'u_1');
    });

    test('a body is bound to the typed request over gRPC as well', () async {
      final user = await grpcClient.createUser(
        const CreateUserRequest(
          email: 'grace@example.com',
          displayName: 'Grace Hopper',
          role: UserRole.userRoleMember,
        ),
      );

      expect(user.id, 'u_2');
      expect(user.email, 'grace@example.com');
      expect(user.role, UserRole.userRoleMember);
    });

    test('a missing resource keeps the status of the contract', () async {
      await expectLater(
        grpcClient.getUser(const GetUserRequest(id: 'nope')),
        throwsA(
          isA<LaskaApiException>()
              .having((error) => error.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('the middleware of the service runs over gRPC too', () async {
      final calls = <String>[];
      app.use((request, next) async {
        calls.add(request.path);
        return next();
      });

      await grpcClient.getUser(const GetUserRequest(id: 'u_1'));

      expect(calls, <String>['/users.v1.UsersService/GetUser']);
    });

    test('the service is not exposed over gRPC when it is not wanted',
        () async {
      final other = Laska();
      registerUsersService(other, UsersServiceImpl(), grpc: false);

      expect(other.grpc.services, isEmpty);
    });
  });
}
