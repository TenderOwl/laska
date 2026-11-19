import 'dart:convert';
import 'dart:io';

import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:contract_slice_example/service.dart';
import 'package:laska_contracts/laska_contracts.dart';
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('vertical slice', () {
    late HttpServer server;
    late UsersServiceClient client;

    setUp(() async {
      final app = Laska();
      registerUsersService(app, UsersServiceImpl());
      server = await serve(app, port: 0);
      client = UsersServiceClient(baseUrl: 'http://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('the generated client talks to the generated endpoint', () async {
      final user = await client.getUser(const GetUserRequest(id: 'u_1'));

      expect(user.id, 'u_1');
      expect(user.email, 'ada@example.com');
      expect(user.displayName, 'Ada Lovelace');
      expect(user.role, UserRole.userRoleAdmin);
      expect(user.tags, <String>['founder', 'mathematician']);
    });

    test('a missing resource is reported as a problem document', () async {
      await expectLater(
        client.getUser(const GetUserRequest(id: 'nope')),
        throwsA(
          isA<LaskaApiException>()
              .having((error) => error.statusCode, 'statusCode', 404)
              .having(
                (error) => jsonDecode(error.body)['code'],
                'code',
                'user_not_found',
              ),
        ),
      );
    });

    test('a query parameter is parsed into the typed request', () async {
      final response = await client.listUsers(
        const ListUsersRequest(limit: 1, cursor: ''),
      );

      expect(response.users, hasLength(1));
      expect(response.users.first.id, 'u_1');
    });

    test('a body is bound to the typed request', () async {
      final user = await client.createUser(
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

    test('an unknown route answers with 404 and a problem document', () async {
      final response = await HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/v1/nothing'))
          .then((request) => request.close());

      expect(response.statusCode, 404);
      final body = await response.transform(utf8.decoder).join();
      expect(jsonDecode(body)['title'], 'Not Found');
    });

    test('a wrong method answers with 405 and an Allow header', () async {
      final response = await HttpClient()
          .deleteUrl(Uri.parse('http://127.0.0.1:${server.port}/v1/users/u_1'))
          .then((request) => request.close());

      expect(response.statusCode, 405);
      expect(response.headers.value('allow'), contains('GET'));
    });
  });

  group('generated artefacts', () {
    test('the OpenAPI document describes the contract', () {
      final document = jsonDecode(
        File('lib/generated/openapi.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(document['openapi'], '3.1.0');
      final paths = document['paths'] as Map<String, dynamic>;
      expect(paths.keys, contains('/v1/users/{id}'));
      expect(paths.keys, contains('/v1/users'));

      final get = paths['/v1/users/{id}'] as Map<String, dynamic>;
      final operation = get['get'] as Map<String, dynamic>;
      expect(operation['operationId'], 'UsersService.GetUser');

      final schemas = (document['components']
          as Map<String, dynamic>)['schemas'] as Map<String, dynamic>;
      expect(schemas.keys, contains('User'));
      expect(schemas.keys, contains('UserRole'));
    });

    test('the checked in code is in sync with the contract', () {
      final contract = File('api/users.proto').readAsStringSync();
      final result = ContractCompiler().compile(<ProtoSource>[
        ProtoSource('users.proto', contract),
      ]);

      final generated = result.files
          .firstWhere((file) => file.path == 'users.pb.dart')
          .content;
      final checkedIn = File('lib/generated/users.pb.dart').readAsStringSync();

      expect(
        _withUnixLineFeeds(checkedIn),
        _withUnixLineFeeds(generated),
        reason: 'Run "laska contract compile" to update the generated code.',
      );
    });
  });
}

/// The line feeds of the file are not part of the code that the compiler
/// writes: a checkout of the repository on Windows can bring the carriage
/// returns along, and the comparison must not depend on them.
String _withUnixLineFeeds(String code) => code.replaceAll('\r\n', '\n');
