import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _base = '''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  string email = 2;
}

message GetUserRequest {
  string id = 1;
}

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }
}
''';

Contract _contract(String source) => Contract(<ProtoFile>[
      ProtoParser(source, fileName: 'users.proto').parse(),
    ]);

void main() {
  group('diffContracts', () {
    test('reports no changes for an identical contract', () {
      final diff = diffContracts(_contract(_base), _contract(_base));

      expect(diff.changes, isEmpty);
      expect(diff.hasBreakingChanges, isFalse);
      expect(diff.report(), 'No changes detected.');
    });

    test('detects a removed field as breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract('''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
}

message GetUserRequest {
  string id = 1;
}

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }
}
'''),
      );

      expect(diff.hasBreakingChanges, isTrue);
      expect(diff.breakingChanges.single.subject, 'users.v1.User.email');
      expect(diff.breakingChanges.single.message, 'field was removed');
    });

    test('detects a changed field number as breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract(_base.replaceAll('string email = 2;', 'string email = 3;')),
      );

      expect(diff.hasBreakingChanges, isTrue);
      expect(diff.breakingChanges.single.message, contains('field number'));
    });

    test('detects a changed field type as breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract(_base.replaceAll('string email = 2;', 'int32 email = 2;')),
      );

      expect(diff.hasBreakingChanges, isTrue);
      expect(diff.breakingChanges.single.message, contains('field type'));
    });

    test('detects an added field as non breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract(
          _base.replaceAll(
            'string email = 2;',
            'string email = 2;\n  string nickname = 3;',
          ),
        ),
      );

      expect(diff.hasBreakingChanges, isFalse);
      expect(diff.changes.single.message, 'field was added');
    });

    test('detects a removed method as breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract('''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  string email = 2;
}

message GetUserRequest {
  string id = 1;
}

service UsersService {
}
'''),
      );

      expect(diff.hasBreakingChanges, isTrue);
      expect(
        diff.breakingChanges.map((change) => change.subject),
        contains('users.v1.UsersService.GetUser'),
      );
    });

    test('detects a changed HTTP binding as breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract(
          _base.replaceAll('/v1/users/{id}', '/v1/users/by-id/{id}'),
        ),
      );

      expect(diff.hasBreakingChanges, isTrue);
      expect(diff.breakingChanges.single.message, contains('HTTP binding'));
    });

    test('detects a removed message as breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract('''
syntax = "proto3";

package users.v1;

message GetUserRequest {
  string id = 1;
}
'''),
      );

      expect(diff.hasBreakingChanges, isTrue);
      expect(
        diff.breakingChanges.map((change) => change.subject),
        contains('users.v1.User'),
      );
    });

    test('detects an added method as non breaking', () {
      final diff = diffContracts(
        _contract(_base),
        _contract('''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  string email = 2;
}

message GetUserRequest {
  string id = 1;
}

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }

  rpc ListUsers(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users" };
  }
}
'''),
      );

      expect(diff.hasBreakingChanges, isFalse);
      expect(
        diff.changes.map((change) => change.subject),
        contains('users.v1.UsersService.ListUsers'),
      );
    });

    test('renders a report', () {
      final diff = diffContracts(
        _contract(_base),
        _contract(_base.replaceAll('string email = 2;', 'int32 email = 2;')),
      );

      expect(diff.report(), contains('BREAKING'));
      expect(diff.report(), contains('1 breaking change(s)'));
    });
  });
}
