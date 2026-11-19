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

  // DeleteUser removes a user.
  rpc DeleteUser(DeleteUserRequest) returns (UserRole) {
    option (google.api.http) = { delete: "/v1/users/{id}" };
  }

  // CreateUser creates a user.
  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = { post: "/v1/users" body: "*" };
  }
}

message User {
  string id = 1;
  UserRole role = 2;
}

enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;
  USER_ROLE_ADMIN = 1;
}

message GetUserRequest {
  string id = 1;
}

message DeleteUserRequest {
  string id = 1;
}

message CreateUserRequest {
  string email = 1;
}
''';

const String _grpcOnlySource = '''
syntax = "proto3";

package users.v1;

// PingService answers over gRPC only.
service PingService {
  // Ping answers with the moment of the call.
  rpc Ping(PingRequest) returns (PingRequest);
}

message PingRequest {
  string id = 1;
}
''';

String _code(String source) => ContractCompiler()
    .compile(<ProtoSource>[
      ProtoSource('users.proto', source),
    ])
    .files
    .single
    .content;

void main() {
  group('the gRPC projection of a contract', () {
    late String code;

    setUp(() {
      code = _code(_contractSource);
    });

    test('registers the service under the name of the contract', () {
      expect(code, contains("name: 'users.v1.UsersService',"));
      expect(code, contains('app.grpc.add('));
    });

    test('reads the request message out of the bytes of the call', () {
      expect(
        code,
        contains(
          'final request = GetUserRequest.fromProtoBytes(bytes);',
        ),
      );
    });

    test('writes the answer of the service in the same format', () {
      expect(code, contains('return response.toProtoBytes();'));
    });

    test('registers the methods under the name of the contract', () {
      expect(code, contains("'GetUser': (bytes) async {"));
      expect(code, contains("'DeleteUser': (bytes) async {"));
    });

    test('the middleware of the route runs over gRPC as well', () {
      expect(code, contains('middleware: middleware,'));
    });

    test('the service can be kept away from gRPC', () {
      expect(code, contains('bool grpc = true,'));
      expect(code, contains('if (grpc) {'));
    });

    test('an enum answer is a bare number on the wire', () {
      expect(code, contains('protoWriter.writeRawVarint(response.number);'));
      expect(code, contains('return protoWriter.toBytes();'));
    });

    test('the client sends the whole request message over gRPC', () {
      expect(
        code,
        contains(
          'final body = _transport.bodyFormat == BodyFormat.protobuf',
        ),
      );
      expect(code, contains('? request.toProtoBytes()'));
    });

    test('the client keeps the body of the REST projection', () {
      expect(
        code,
        contains(': utf8.encode(jsonEncode(request.toJson()));'),
      );
    });
  });

  group('a service without an HTTP binding', () {
    late String code;

    setUp(() {
      code = _code(_grpcOnlySource);
    });

    test('is registered over gRPC', () {
      expect(code, contains('app.grpc.add('));
      expect(code, contains("name: 'users.v1.PingService',"));
      expect(code, contains("'Ping': (bytes) async {"));
    });

    test('has no REST projection', () {
      expect(code, isNot(contains("app.get(")));
      expect(code, isNot(contains("app.post(")));
    });

    test('is reported by the compiler', () {
      final result = ContractCompiler().compile(<ProtoSource>[
        ProtoSource('users.proto', _grpcOnlySource),
      ]);

      expect(
        result.warnings,
        contains(
          'Method "users.v1.PingService.Ping" has no google.api.http binding '
          'and is therefore exposed over gRPC only.',
        ),
      );
    });
  });
}
