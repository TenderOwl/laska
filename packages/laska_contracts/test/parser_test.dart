import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

ProtoFile _parse(String source) =>
    ProtoParser(source, fileName: 'test.proto').parse();

void main() {
  group('ProtoParser', () {
    test('parses a package, messages and fields', () {
      final file = _parse('''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  int32 age = 2;
  repeated string tags = 3;
  optional string nickname = 4;
}
''');

      expect(file.package, 'users.v1');
      expect(file.messages, hasLength(1));

      final user = file.messages.first;
      expect(user.name, 'User');
      expect(user.fullName, 'users.v1.User');
      expect(user.fields, hasLength(4));

      expect(user.fields[0].name, 'id');
      expect(user.fields[0].number, 1);
      expect(user.fields[0].type, 'string');
      expect(user.fields[0].repeated, isFalse);
      expect(user.fields[0].optional, isFalse);

      expect(user.fields[1].type, 'int32');
      expect(user.fields[2].repeated, isTrue);
      expect(user.fields[3].optional, isTrue);
    });

    test('parses enums with their values', () {
      final file = _parse('''
syntax = "proto3";

enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;
  USER_ROLE_ADMIN = 1;
}
''');

      final role = file.enums.first;
      expect(role.name, 'UserRole');
      expect(role.values.map((value) => value.name), <String>[
        'USER_ROLE_UNSPECIFIED',
        'USER_ROLE_ADMIN',
      ]);
      expect(role.values.last.number, 1);
    });

    test('parses services and google.api.http bindings', () {
      final file = _parse('''
syntax = "proto3";

package users.v1;

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }

  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = { post: "/v1/users" body: "*" };
  }
}

message GetUserRequest { string id = 1; }
message CreateUserRequest { string email = 1; }
message User { string id = 1; }
''');

      final service = file.services.first;
      expect(service.name, 'UsersService');
      expect(service.methods, hasLength(2));

      final get = service.methods.first;
      expect(get.name, 'GetUser');
      expect(get.requestType, 'users.v1.GetUserRequest');
      expect(get.responseType, 'users.v1.User');
      expect(get.httpRules.single.method, 'GET');
      expect(get.httpRules.single.path, '/v1/users/{id}');
      expect(get.httpRules.single.pathParameters, <String>['id']);

      final create = service.methods.last;
      expect(create.httpRules.single.method, 'POST');
      expect(create.httpRules.single.body, '*');
    });

    test('parses additional bindings', () {
      final file = _parse('''
syntax = "proto3";

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = {
      get: "/v1/users/{id}"
      additional_bindings {
        post: "/v1/users:lookup"
        body: "*"
      }
    };
  }
}

message GetUserRequest { string id = 1; }
message User { string id = 1; }
''');

      final rules = file.services.first.methods.first.httpRules;
      expect(rules, hasLength(2));
      expect(rules[0].path, '/v1/users/{id}');
      expect(rules[1].method, 'POST');
      expect(rules[1].path, '/v1/users:lookup');
      expect(rules[1].body, '*');
    });

    test('keeps documentation comments', () {
      final file = _parse('''
syntax = "proto3";

// A user of the application.
message User {
  // Stable identifier of the user.
  string id = 1;
}
''');

      expect(file.messages.first.comment, 'A user of the application.');
      expect(file.messages.first.fields.first.comment,
          'Stable identifier of the user.');
    });

    test('records imports without resolving them', () {
      final file = _parse('''
syntax = "proto3";

import "google/api/annotations.proto";
''');

      expect(file.imports, <String>['google/api/annotations.proto']);
    });

    test('rejects constructs that are not supported yet', () {
      expect(
        () => _parse(
            'syntax = "proto3"; message A { extend B { string a = 1; } }'),
        throwsA(isA<ProtoParseException>()),
      );
    });

    test('rejects a contract that is not proto3', () {
      expect(
        () => _parse('syntax = "proto2";'),
        throwsA(isA<ProtoParseException>()),
      );
    });
  });
}
