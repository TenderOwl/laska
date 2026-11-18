import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _v1 = '''
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

/// The same contract with one field more and one method more.
const String _v1Added = '''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  string email = 2;
  string name = 3;
}

message GetUserRequest {
  string id = 1;
}

message ListUsersRequest {
  int page = 1;
}

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }

  rpc ListUsers(ListUsersRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users" };
  }
}
''';

const String _v2 = '''
syntax = "proto3";

package users.v2;

message User {
  string id = 1;
  string email = 2;
}

message GetUserRequest {
  string id = 1;
}

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v2/users/{id}" };
  }
}
''';

/// The same contract with a field of another type.
const String _v1OtherType = '''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  int64 email = 2;
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
  group('analyzeCompatibility', () {
    test('a client works against the same version of the server', () {
      final report = analyzeCompatibility(_contract(_v1), _contract(_v1));

      expect(report.compatibility, Compatibility.compatible);
      expect(report.isDeployable, isTrue);
      expect(report.issues, isEmpty);
    });

    test('a client of the old version works against a server that added', () {
      final report = analyzeCompatibility(_contract(_v1), _contract(_v1Added));

      expect(report.compatibility, Compatibility.compatible);
      expect(report.isDeployable, isTrue);
    });

    test('a client of the new version misses what the old server does not have',
        () {
      final report = analyzeCompatibility(_contract(_v1Added), _contract(_v1));

      expect(report.compatibility, Compatibility.partial);
      expect(report.isDeployable, isFalse);
      expect(
        report.issues.map((issue) => issue.subject),
        containsAll(<String>['UsersService.ListUsers', 'User.name']),
      );
      expect(
        report.issues
            .where((issue) => issue.subject == 'UsersService.ListUsers')
            .single
            .kind,
        CompatibilityIssueKind.missingMethod,
      );
      expect(
        report.issues
            .where((issue) => issue.subject == 'User.name')
            .single
            .kind,
        CompatibilityIssueKind.missingField,
      );
    });

    test('a client cannot work against a server that changed a type', () {
      final report =
          analyzeCompatibility(_contract(_v1), _contract(_v1OtherType));

      expect(report.compatibility, Compatibility.incompatible);
      expect(report.isDeployable, isFalse);
      expect(report.fatalIssues.single.subject, 'User.email');
      expect(
        report.fatalIssues.single.kind,
        CompatibilityIssueKind.changedFieldType,
      );
    });

    test('a client cannot work against a server that has no service', () {
      final report = analyzeCompatibility(
        _contract(_v1),
        Contract(<ProtoFile>[
          ProtoParser(
            '''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
}
''',
            fileName: 'users.proto',
          ).parse(),
        ]),
      );

      expect(report.compatibility, Compatibility.incompatible);
      expect(report.fatalIssues.single.kind,
          CompatibilityIssueKind.missingService);
    });

    test('the version of the API changes the paths, not the contract', () {
      final report = analyzeCompatibility(_contract(_v1), _contract(_v2));

      expect(report.compatibility, Compatibility.compatible);
      expect(report.isDeployable, isFalse);
      expect(report.pathIssues.single.kind, CompatibilityIssueKind.changedPath);
      expect(report.pathIssues.single.message, contains('/v1/users/{id}'));
      expect(report.pathIssues.single.message, contains('/v2/users/{id}'));
    });
  });

  group('buildCompatibilityMatrix', () {
    test('every version works against itself', () {
      final matrix = buildCompatibilityMatrix(<String, Contract>{
        'v1': _contract(_v1),
        'v2': _contract(_v2),
      });

      expect(matrix.versions, <String>['v1', 'v2']);
      expect(matrix.report('v1', 'v1').isDeployable, isTrue);
      expect(matrix.report('v2', 'v2').isDeployable, isTrue);
    });

    test('the matrix tells which servers a client works against', () {
      final matrix = buildCompatibilityMatrix(<String, Contract>{
        'v1': _contract(_v1),
        'v1+': _contract(_v1Added),
      });

      expect(matrix.serversFor('v1'), <String>['v1', 'v1+']);
      expect(matrix.serversFor('v1+'), <String>['v1+']);
      expect(matrix.clientsFor('v1'), <String>['v1']);
      expect(matrix.clientsFor('v1+'), <String>['v1', 'v1+']);
    });

    test('the matrix is not fully compatible when a version moves', () {
      final matrix = buildCompatibilityMatrix(<String, Contract>{
        'v1': _contract(_v1),
        'v2': _contract(_v2),
      });

      expect(matrix.isFullyCompatible, isFalse);
      expect(matrix.serversFor('v1'), <String>['v1']);
    });

    test('the table of the matrix reads the compatibility of every pair', () {
      final matrix = buildCompatibilityMatrix(<String, Contract>{
        'v1': _contract(_v1),
        'v2': _contract(_v2),
      });

      final table = matrix.table();
      expect(table, contains('yes'));
      expect(table, contains('*'));
      expect(table, contains('the REST paths of the two versions differ'));
    });

    test('the markdown of the matrix is a table', () {
      final matrix = buildCompatibilityMatrix(<String, Contract>{
        'v1': _contract(_v1),
        'v2': _contract(_v2),
      });

      final markdown = matrix.markdown();
      expect(markdown, startsWith('| client \\ server | v1 | v2 |'));
      expect(markdown, contains('| v1 | yes | yes* |'));
      expect(markdown, contains('| v2 | yes* | yes |'));
    });

    test('the details of the matrix explain every pair', () {
      final matrix = buildCompatibilityMatrix(<String, Contract>{
        'v1': _contract(_v1),
        'v1+': _contract(_v1Added),
      });

      final details = matrix.details();
      expect(
          details, contains('v1 -> v1: the client works against the server'));
      expect(
        details,
        contains('v1+ -> v1: the client works, but the server lacks a part'),
      );
    });

    test('the matrix refuses a pair it does not know', () {
      final matrix = buildCompatibilityMatrix(<String, Contract>{
        'v1': _contract(_v1),
      });

      expect(
        () => matrix.report('v1', 'v9'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
