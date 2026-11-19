import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _source = '''
syntax = "proto3";

package users.v1;

import "google/protobuf/timestamp.proto";

// UsersService manages the accounts of the application.
service UsersService {
  // GetUser returns a single user by its identifier.
  rpc GetUser(GetUserRequest) returns (User);

  // DeleteUser removes a user.
  rpc DeleteUser(DeleteUserRequest) returns (UserRole);
}

// A user of the application.
message User {
  // Stable identifier of the user.
  string id = 1;

  // Role of the user.
  UserRole role = 2;

  // Free form tags.
  repeated string tags = 3;

  // The moment the account was created.
  google.protobuf.Timestamp created_at = 4;

  // The nickname, when it is known.
  optional string nickname = 5;

  // The scores of the user.
  map<string, int32> scores = 6;
}

// The role a user has.
enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;
  USER_ROLE_ADMIN = 1;
}

// A subscription of a user to a plan.
message Subscription {
  // The plan of the subscription.
  message Plan {
    string name = 1;
  }

  // The state of the subscription.
  enum State {
    SUBSCRIPTION_STATE_ACTIVE = 0;
  }

  // The plan of the subscription.
  Plan plan = 1;

  // How the subscription is paid.
  oneof payment {
    string card_token = 2;
    string iban = 3;
  }
}

message GetUserRequest {
  string id = 1;
}

message DeleteUserRequest {
  string id = 1;
}
''';

const String _edgeSource = '''
syntax = "proto3";

package edge.v1;

// EdgeService exercises the corners of the wire format.
service EdgeService {
  // Role answers with an enum.
  rpc Role(EdgeRequest) returns (EdgeRole);
}

message EdgeRequest {
  // The numbers of the call.
  repeated int32 numbers = 1;

  // The count of the call.
  sint64 count = 2;
}

enum EdgeRole {
  EDGE_ROLE_UNSPECIFIED = 0;
}
''';

Contract _contract() => ContractCompiler()
    .build(<ProtoSource>[ProtoSource('users.proto', _source)]);

Contract _edgeContract() => ContractCompiler()
    .build(<ProtoSource>[ProtoSource('edge.proto', _edgeSource)]);

List<GeneratedFile> _generate({String module = 'example.com/laska/users'}) =>
    GoGenerator(_contract(), module: module).generate();

String _fileOf(List<GeneratedFile> files, String path) {
  for (final file in files) {
    if (file.path == path) {
      return file.content;
    }
  }
  throw StateError('The SDK holds no file "$path".');
}

void main() {
  group('The Go SDK of a contract', () {
    test('holds the module, the runtime and the files of the contract', () {
      final files = _generate();
      final paths = files.map((file) => file.path).toList();

      expect(paths, contains('go.mod'));
      expect(paths, contains('internal/wire/wire.go'));
      expect(paths, contains('internal/grpc/grpc.go'));
      expect(paths, contains('wellknown.pb.go'));
      expect(paths, contains('client.go'));
      expect(paths, contains('users.pb.go'));
      expect(paths, contains('users_client.pb.go'));
    });

    test('names the module and the package after the path of the module', () {
      final files = _generate();

      expect(
        _fileOf(files, 'go.mod'),
        contains('module example.com/laska/users'),
      );
      expect(_fileOf(files, 'go.mod'), contains('go 1.24'));
      expect(_fileOf(files, 'users.pb.go'), contains('package users'));
    });

    test('holds the name of the package of the module', () {
      expect(
        GoGenerator.packageNameOf('example.com/laska/users'),
        'users',
      );
      expect(
        GoGenerator.packageNameOf('example.com/laska/users.v2'),
        'users_v2',
      );
      expect(GoGenerator.packageNameOf('example.com/laska/type'), 'type_');
    });

    test('holds the runtime the SDK needs', () {
      final files = _generate();

      expect(
        _fileOf(files, 'internal/wire/wire.go'),
        contains('package wire'),
      );
      expect(
        _fileOf(files, 'internal/grpc/grpc.go'),
        contains('package grpc'),
      );
    });

    test('writes the types of the messages of the contract', () {
      final files = _generate();
      final source = _fileOf(files, 'users.pb.go');

      expect(source, contains('type User struct {'));
      expect(source, contains('Id string'));
      expect(source, contains('Role UserRole'));
      expect(source, contains('Tags []string'));
      expect(source, contains('CreatedAt *ProtoTimestamp'));
      expect(source, contains('Nickname *string'));
      expect(source, contains('Scores map[string]int32'));
    });

    test('writes the enums of the contract as numbers', () {
      final files = _generate();
      final source = _fileOf(files, 'users.pb.go');

      expect(source, contains('type UserRole int32'));
      expect(source, contains('UserRoleUnspecified UserRole = 0'));
      expect(source, contains('UserRoleAdmin UserRole = 1'));
      expect(source, contains('func (e UserRole) String() string {'));
    });

    test('writes the nested types of a message after their scope', () {
      final files = _generate();
      final source = _fileOf(files, 'users.pb.go');

      expect(source, contains('type SubscriptionPlan struct {'));
      expect(source, contains('type SubscriptionState int32'));
      expect(source, contains('Plan *SubscriptionPlan'));
    });

    test('writes the members of a group of a oneof behind a pointer', () {
      final files = _generate();
      final source = _fileOf(files, 'users.pb.go');

      expect(source, contains('CardToken *string'));
      expect(source, contains('Iban *string'));
    });

    test('writes the message on the wire with the numbers of the fields', () {
      final files = _generate();
      final source = _fileOf(files, 'users.pb.go');

      expect(source, contains('func (m *User) MarshalProto() []byte {'));
      expect(source, contains('w.WriteString(1, m.Id)'));
      expect(source, contains('w.WriteEnum(2, int32(m.Role))'));
      expect(source, contains('w.WriteMessage(4, m.CreatedAt)'));
      expect(source, contains('w.WriteString(5, *m.Nickname)'));
    });

    test('reads the message out of its bytes', () {
      final files = _generate();
      final source = _fileOf(files, 'users.pb.go');

      expect(source,
          contains('func (m *User) UnmarshalProto(data []byte) error {'));
      expect(source, contains('m.Id = value'));
      expect(source, contains('m.Role = UserRole(number)'));
      expect(source, contains('item := &ProtoTimestamp{}'));
    });

    test('writes the getters of the fields of a message', () {
      final files = _generate();
      final source = _fileOf(files, 'users.pb.go');

      expect(source, contains('func (m *User) GetId() string {'));
      expect(source, contains('func (m *User) GetTags() []string {'));
      expect(
          source, contains('func (m *User) GetCreatedAt() *ProtoTimestamp {'));
      expect(
          source, contains('func (m *Subscription) GetCardToken() string {'));
    });

    test('writes the well-known types of the protocol buffers', () {
      final files = _generate();
      final source = _fileOf(files, 'wellknown.pb.go');

      expect(source, contains('type ProtoTimestamp struct {'));
      expect(source, contains('type ProtoDuration struct {'));
      expect(source, contains('type ProtoAny struct {'));
      expect(source, contains('type ProtoEmpty struct {'));
    });

    test('writes the clients of the services of the contract', () {
      final files = _generate();
      final source = _fileOf(files, 'users_client.pb.go');

      expect(source, contains('type UsersServiceClient struct {'));
      expect(source, contains('func NewUsersServiceClient(target string'));
      expect(
        source,
        contains(
          'func (c *UsersServiceClient) GetUser(ctx context.Context, '
          'request *GetUserRequest, opts ...CallOptions) (*User, error) {',
        ),
      );
      expect(source, contains('"/users.v1.UsersService/GetUser"'));
      expect(source, contains('"/users.v1.UsersService/DeleteUser"'));
    });

    test('reads the answer of a method that answers with an enum', () {
      final files = _generate();
      final source = _fileOf(files, 'users_client.pb.go');

      expect(source, contains('number, err := wire.ReadRawVarint(raw)'));
      expect(source, contains('return UserRole(int32(number)), nil'));
    });

    test('holds the options of the calls of the clients', () {
      final files = _generate();
      final source = _fileOf(files, 'client.go');

      expect(source, contains('type CallOptions struct {'));
      expect(source, contains('Timeout time.Duration'));
      expect(source, contains('Metadata map[string]string'));
    });

    test('holds the failure of a call with the status of the service', () {
      final files = _generate();
      final source = _fileOf(files, 'client.go');

      expect(source, contains('type StatusError struct {'));
      expect(source, contains('Code int'));
      expect(source, contains('Message string'));
      expect(source, contains('StatusNotFound = 5'));
      expect(source, contains('func statusErrorOf(err error) error {'));
    });
  });

  group('The Go SDK of the corners of the wire format', () {
    test('writes the values of a packed field the way protobuf writes them',
        () {
      final files =
          GoGenerator(_edgeContract(), module: 'example.com/laska/edge')
              .generate();
      final source = _fileOf(files, 'edge.pb.go');

      // A number of 32 bits that is negative takes ten bytes on the wire.
      expect(source, contains('packed.WriteRawVarint(uint64(int64(value)))'));
      expect(source, contains('w.WriteSint64(2, m.Count)'));
    });

    test('answers with the value of an enum when the call fails', () {
      final files =
          GoGenerator(_edgeContract(), module: 'example.com/laska/edge')
              .generate();
      final source = _fileOf(files, 'edge_client.pb.go');

      expect(source, contains('return EdgeRole(0), statusErrorOf(err)'));
      expect(source, contains('return EdgeRole(int32(number)), nil'));
    });
  });
}
