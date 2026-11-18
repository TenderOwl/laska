import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

Contract _contract(String source) => Contract(<ProtoFile>[
      ProtoParser(source, fileName: 'users.proto').parse(),
    ]);

void main() {
  group('lintContract', () {
    test('accepts a contract that follows the rules', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  string display_name = 2;
}

enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;
  USER_ROLE_ADMIN = 1;
}

service UsersService {
  rpc GetUser(GetUserRequest) returns (User);
}

message GetUserRequest {
  string id = 1;
}
'''));

      expect(problems, isEmpty);
    });

    test('reports a package that is not versioned', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users;

message User {
  string id = 1;
}
'''));

      expect(problems, hasLength(1));
      expect(problems.single.subject, 'users');
      expect(problems.single.message, contains('not versioned'));
    });

    test('reports a file that does not match its package', () {
      final problems = lintContract(
        Contract(<ProtoFile>[
          ProtoParser(
            '''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
}
''',
            fileName: 'accounts.proto',
          ).parse(),
        ]),
      );

      expect(problems, hasLength(1));
      expect(problems.single.message, contains('accounts.proto'));
    });

    test('reports a message that is not written in PascalCase', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users.v1;

message user_profile {
  string id = 1;
}
'''));

      expect(problems, hasLength(1));
      expect(problems.single.message, contains('PascalCase'));
    });

    test('reports a field that is not written in snake_case', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users.v1;

message User {
  string displayName = 1;
}
'''));

      expect(problems, hasLength(1));
      expect(problems.single.subject, 'users.v1.User.displayName');
      expect(problems.single.message, contains('snake_case'));
    });

    test('reports a value of an enum that is not in upper case', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users.v1;

enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;
  userRoleAdmin = 1;
}
'''));

      expect(problems, hasLength(1));
      expect(problems.single.message, contains('UPPER_SNAKE_CASE'));
    });

    test('reports a service that does not end with Service', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users.v1;

service Users {
  rpc GetUser(GetUserRequest) returns (User);
}

message GetUserRequest {
  string id = 1;
}

message User {
  string id = 1;
}
'''));

      expect(problems, hasLength(1));
      expect(problems.single.message, contains('ends with "Service"'));
    });

    test('reports a method that is not written in PascalCase', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users.v1;

service UsersService {
  rpc getUser(GetUserRequest) returns (User);
}

message GetUserRequest {
  string id = 1;
}

message User {
  string id = 1;
}
'''));

      expect(problems, hasLength(1));
      expect(problems.single.message, contains('PascalCase'));
    });

    test('names the file and the subject of a problem', () {
      final problems = lintContract(_contract('''
syntax = "proto3";

package users.v1;

message user_profile {
  string id = 1;
}
'''));

      expect(problems.single.toString(), contains('users.proto'));
      expect(problems.single.toString(), contains('users.v1.user_profile'));
    });
  });
}
