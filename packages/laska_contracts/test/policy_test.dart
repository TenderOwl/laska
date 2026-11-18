import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _contract = '''
syntax = "proto3";

package users.v1;

import "google/api/annotations.proto";

service UsersService {
  option (laska.policy) = {
    timeout_ms: 1500
    max_attempts: 4
    backoff_ms: 250
    max_backoff_ms: 5000
    jitter: true
  };

  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
    option (laska.policy) = { idempotent: true };
  }

  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = { post: "/v1/users" body: "*" };
    option (laska.policy) = { timeout_ms: 500, idempotent: false };
  }
}

message User {
  string id = 1;
  string email = 2;
  UserRole role = 3;
  repeated string tags = 4;
}

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

Contract _parse([String source = _contract]) => Contract(<ProtoFile>[
      ProtoParser(source, fileName: 'users.proto').parse(),
    ]);

MethodPolicy? _policyOf(Contract contract, String method) {
  final service = contract.services.first;
  return service.methods.firstWhere((value) => value.name == method).policy;
}

void main() {
  group('the policy of a contract', () {
    test('is read from the annotation of a service', () {
      final contract = _parse();

      final policy = contract.services.first.policy!;

      expect(policy.timeout, const Duration(milliseconds: 1500));
      expect(policy.maxAttempts, 4);
      expect(policy.backoff, const Duration(milliseconds: 250));
      expect(policy.maxBackoff, const Duration(milliseconds: 5000));
      expect(policy.jitter, isTrue);
      expect(policy.idempotent, isNull);
    });

    test('is read from the annotation of a method', () {
      final contract = _parse();

      expect(_policyOf(contract, 'GetUser')!.idempotent, isTrue);
      expect(_policyOf(contract, 'CreateUser')!.timeout,
          const Duration(milliseconds: 500));
      expect(_policyOf(contract, 'CreateUser')!.idempotent, isFalse);
    });

    test('is merged with the policy of the service', () {
      final service = _parse().services.first;
      final method = service.methods.firstWhere(
        (value) => value.name == 'CreateUser',
      );

      final merged = service.policy!.merge(method.policy);

      expect(merged.timeout, const Duration(milliseconds: 500));
      expect(merged.maxAttempts, 4);
      expect(merged.backoff, const Duration(milliseconds: 250));
      expect(merged.idempotent, isFalse);
    });

    test('is rejected when a key is unknown', () {
      expect(
        () => _parse('''
syntax = "proto3";

package users.v1;

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (laska.policy) = { unknown_key: 1 };
  }
}

message GetUserRequest { string id = 1; }
message User { string id = 1; }
'''),
        throwsA(isA<ProtoParseException>()),
      );
    });

    test('is rejected when a value is of the wrong type', () {
      expect(
        () => _parse('''
syntax = "proto3";

package users.v1;

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (laska.policy) = { idempotent: 3 };
  }
}

message GetUserRequest { string id = 1; }
message User { string id = 1; }
'''),
        throwsA(isA<ProtoParseException>()),
      );
    });
  });

  group('the generated code of a policy', () {
    late String code;

    setUp(() {
      code = ContractCompiler()
          .compile(<ProtoSource>[ProtoSource('users.proto', _contract)])
          .files
          .single
          .content;
    });

    test('holds the policy of every method', () {
      expect(code, contains('class UsersServicePolicies {'));
      expect(code, contains('static final DependencyPolicy getUser'));
      expect(code, contains('static final DependencyPolicy createUser'));
    });

    test('holds the timeout of the contract', () {
      expect(code, contains('timeout: Duration(milliseconds: 1500)'));
    });

    test('holds the retry of the contract', () {
      expect(code, contains('maxAttempts: 4'));
      expect(code, contains('initialBackoff: Duration(milliseconds: 250)'));
      expect(code, contains('maxBackoff: Duration(seconds: 5)'));
      expect(code, contains('jitter: true'));
    });

    test('holds the idempotency of the contract', () {
      expect(code, contains('idempotent: true'));
      expect(code, contains('idempotent: false'));
    });

    test('names the methods of the contract', () {
      expect(code, contains("'GetUser': getUser"));
      expect(code, contains("'CreateUser': createUser"));
    });

    test('gives the client the policy of the methods', () {
      expect(code, contains('...UsersServicePolicies.policies,'));
    });
  });

  group('the generated code of a message', () {
    late String code;

    setUp(() {
      code = ContractCompiler()
          .compile(<ProtoSource>[ProtoSource('users.proto', _contract)])
          .files
          .single
          .content;
    });

    test('writes the message on the wire', () {
      expect(code, contains('List<int> toProtoBytes()'));
      expect(code, contains('writer.writeString(1, id);'));
      expect(code, contains('writer.writeEnum(3, role.number);'));
      expect(code, contains('writer.writeString(4, item);'));
    });

    test('reads the message from the wire', () {
      expect(code, contains('factory User.fromProtoBytes(List<int> bytes)'));
      expect(code, contains('id = reader.readString();'));
      expect(code, contains('role = UserRole.fromNumber(reader.readEnum());'));
      expect(code, contains('tags.add(reader.readString());'));
    });

    test('holds the number of the values of an enum', () {
      expect(
          code,
          contains("userRoleUnspecified('USER_ROLE_UNSPECIFIED', "
              'number: 0)'));
      expect(code, contains('static UserRole fromNumber(int number)'));
    });
  });
}
