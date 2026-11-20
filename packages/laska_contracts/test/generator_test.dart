import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _contractSource = '''
syntax = "proto3";

package users.v1;

import "google/api/annotations.proto";

// UsersService manages the accounts of the application.
service UsersService {
  // GetUser returns a single user by its identifier.
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }

  // CreateUser creates a new user.
  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = { post: "/v1/users" body: "*" };
  }
}

// A user of the application.
message User {
  string id = 1;
  string display_name = 2;
  UserRole role = 3;
  repeated string tags = 4;
}

// The role a user has.
enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;
  USER_ROLE_ADMIN = 1;
}

message GetUserRequest {
  string id = 1;
}

message CreateUserRequest {
  string email = 1;
}
''';

CompileResult _compile([String source = _contractSource]) =>
    ContractCompiler().compile(<ProtoSource>[
      ProtoSource('users.proto', source),
    ]);

void main() {
  group('DartGenerator', () {
    late CompileResult result;

    setUp(() {
      result = _compile();
    });

    String code() => result.files.single.content;

    test('generates one file per proto file', () {
      expect(result.files.single.path, 'users.pb.dart');
    });

    test('generates message classes with typed fields', () {
      expect(code(), contains('class User {'));
      expect(code(), contains('final String displayName;'));
      expect(code(), contains('final UserRole role;'));
      expect(code(), contains('final List<String> tags;'));
      expect(
          code(), contains('factory User.fromJson(Map<String, dynamic> json)'));
      expect(code(), contains('Map<String, dynamic> toJson()'));
    });

    test('generates the enum with its proto names', () {
      expect(code(), contains('enum UserRole {'));
      expect(code(), contains("userRoleAdmin('USER_ROLE_ADMIN', number: 1)"));
      expect(code(), contains('static UserRole fromName('));
    });

    test('generates the service interface', () {
      expect(code(), contains('abstract class UsersService {'));
      expect(code(), contains('Future<User> getUser(GetUserRequest request);'));
    });

    test('generates the REST projection', () {
      expect(code(), contains('void registerUsersService('));
      expect(code(), contains("'/v1/users/:id'"));
      expect(code(), contains('GetUserRequest.fromJson(payload)'));
    });

    test('generates a typed client', () {
      expect(code(), contains('class UsersServiceClient {'));
      expect(code(), contains('Future<User> getUser(GetUserRequest request)'));
      expect(code(), contains('throw LaskaApiException('));
    });

    test('generates a client that takes the headers of the call', () {
      expect(
        code(),
        contains('{String? idempotencyKey, Map<String, String>? headers}'),
      );
      expect(code(), contains('...?headers,'));
    });

    test('the client writes the accept and the content type of the call', () {
      expect(code(), contains("'accept': _transport.bodyFormat"));
      expect(code(), contains("'content-type': _transport.bodyFormat"));
    });

    test('the key of the idempotency of the caller wins', () {
      expect(
        code(),
        contains("requestHeaders['idempotency-key'] = idempotencyKey;"),
      );
      expect(
        code(),
        contains(
          "requestHeaders['idempotency-key'] = newIdempotencyKey();",
        ),
      );
    });

    test('warns about imports that are not part of the contract', () {
      expect(result.warnings.single, contains('google/api/annotations.proto'));
    });
  });

  group('OpenApiGenerator', () {
    late Map<String, dynamic> document;

    setUp(() {
      document = _compile().openapi;
    });

    test('describes the version and the paths', () {
      expect(document['openapi'], '3.1.0');

      final paths = document['paths'] as Map<String, dynamic>;
      expect(paths.keys, contains('/v1/users/{id}'));
      expect(paths.keys, contains('/v1/users'));
    });

    test('describes the operation', () {
      final paths = document['paths'] as Map<String, dynamic>;
      final operation = (paths['/v1/users/{id}'] as Map<String, dynamic>)['get']
          as Map<String, dynamic>;

      expect(operation['operationId'], 'UsersService.GetUser');
      expect(operation['tags'], <String>['UsersService']);
      expect(operation['summary'],
          'GetUser returns a single user by its identifier.');
    });

    test('describes the path parameter', () {
      final paths = document['paths'] as Map<String, dynamic>;
      final operation = (paths['/v1/users/{id}'] as Map<String, dynamic>)['get']
          as Map<String, dynamic>;
      final parameters = operation['parameters'] as List<dynamic>;

      expect(parameters, hasLength(1));
      expect((parameters.first as Map<String, dynamic>)['name'], 'id');
      expect((parameters.first as Map<String, dynamic>)['in'], 'path');
    });

    test('describes the request body', () {
      final paths = document['paths'] as Map<String, dynamic>;
      final operation = (paths['/v1/users'] as Map<String, dynamic>)['post']
          as Map<String, dynamic>;
      final body = operation['requestBody'] as Map<String, dynamic>;

      expect(body['required'], isTrue);
    });

    test('describes the schemas', () {
      final components = document['components'] as Map<String, dynamic>;
      final schemas = components['schemas'] as Map<String, dynamic>;

      expect(schemas.keys, contains('User'));
      expect(schemas.keys, contains('UserRole'));

      final user = schemas['User'] as Map<String, dynamic>;
      final properties = user['properties'] as Map<String, dynamic>;
      expect(properties['displayName'], <String, dynamic>{'type': 'string'});
      expect(properties['tags'], <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
      });
      expect(user['required'], <String>['id', 'displayName', 'role']);
    });
  });

  group('ContractCompiler validation', () {
    test('rejects an unknown field type', () {
      expect(
        () => _compile('''
syntax = "proto3";

message User {
  Unknown id = 1;
}
'''),
        throwsA(
          isA<ContractCompileException>().having(
            (error) => error.problems.single,
            'problem',
            contains('unknown type'),
          ),
        ),
      );
    });

    test('rejects a path parameter that is not a field', () {
      expect(
        () => _compile('''
syntax = "proto3";

message GetUserRequest {
  string id = 1;
}

service UsersService {
  rpc GetUser(GetUserRequest) returns (GetUserRequest) {
    option (google.api.http) = { get: "/v1/users/{uid}" };
  }
}
'''),
        throwsA(
          isA<ContractCompileException>().having(
            (error) => error.problems.single,
            'problem',
            contains('is not a field of'),
          ),
        ),
      );
    });

    test('rejects two messages with the same name', () {
      expect(
        () => _compile('''
syntax = "proto3";

package a;

message User {
  string id = 1;
}

package b;

message User {
  string id = 1;
}
'''),
        throwsA(isA<ContractCompileException>()),
      );
    });
  });
}
