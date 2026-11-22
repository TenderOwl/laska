import 'dart:convert';

import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _usersSource = '''
syntax = "proto3";

package users.v1;

import "google/protobuf/timestamp.proto";

// UsersService manages the accounts of the application.
service UsersService {
  // GetUser returns a single user by its identifier.
  rpc GetUser(GetUserRequest) returns (User);

  // Ping answers over gRPC only.
  rpc Ping(GetUserRequest) returns (User);
}

// A user of the application.
message User {
  // Stable identifier of the user.
  string id = 1;

  // Human readable name.
  string display_name = 2;

  // The role of the user.
  UserRole role = 3;

  // The moment the account was created.
  google.protobuf.Timestamp created_at = 4;

  // The name the user is known by.
  optional string nickname = 5;
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

  // The features of the plan, by their name.
  map<string, bool> features = 2;

  // How the subscription is paid.
  oneof payment {
    string card_token = 3;
    string iban = 4;
  }
}

// Request of the GetUser method.
message GetUserRequest {
  string id = 1;
}
''';

Contract _contract() => ContractCompiler().build(<ProtoSource>[
      ProtoSource('users.proto', _usersSource),
    ]);

/// Reads the fields of the message [bytes].
///
/// The value of a field is a number for a field of a number and the bytes of
/// the field for a field of the bytes or of an embedded message.
Map<int, List<Object>> _parse(List<int> bytes) {
  final fields = <int, List<Object>>{};
  var position = 0;

  int readVarint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = bytes[position++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return value;
      }
      shift += 7;
    }
  }

  while (position < bytes.length) {
    final tag = readVarint();
    final field = tag >> 3;
    final wireType = tag & 0x7;

    Object value;
    if (wireType == 0) {
      value = readVarint();
    } else if (wireType == 2) {
      final length = readVarint();
      value = bytes.sublist(position, position + length);
      position += length;
    } else {
      throw StateError('The wire type $wireType is not supported.');
    }

    (fields[field] ??= <Object>[]).add(value);
  }

  return fields;
}

/// The values of the field [field] of the message [bytes].
List<Object> _field(Map<int, List<Object>> message, int field) =>
    message[field] ?? const <Object>[];

/// The name of the field [field] of the message [bytes].
String _name(List<int> bytes) => _string(_parse(bytes), 1);

/// The value of the field [field] of the message [message].
String _string(Map<int, List<Object>> message, int field) =>
    utf8.decode(_field(message, field).first as List<int>);

/// The values of the field [field] of the message [message].
List<String> _strings(Map<int, List<Object>> message, int field) => _field(
      message,
      field,
    ).cast<List<int>>().map(utf8.decode).toList(growable: false);

/// The files of the descriptor [descriptor].
List<List<int>> _filesOf(List<int> descriptor) =>
    _field(_parse(descriptor), 1).cast<List<int>>().toList(growable: false);

/// The file of the descriptor [descriptor] named [name].
Map<int, List<Object>> _fileOf(List<int> descriptor, String name) {
  for (final file in _filesOf(descriptor)) {
    if (_name(file) == name) {
      return _parse(file);
    }
  }
  fail('The descriptor holds no file named "$name".');
}

/// The message of the file [file] named [name].
Map<int, List<Object>> _messageOf(Map<int, List<Object>> file, String name) {
  for (final message in _field(file, 4).cast<List<int>>()) {
    if (_name(message) == name) {
      return _parse(message);
    }
  }
  fail('The file holds no message named "$name".');
}

/// The service of the file [file] named [name].
Map<int, List<Object>> _serviceOf(Map<int, List<Object>> file, String name) {
  for (final service in _field(file, 6).cast<List<int>>()) {
    if (_name(service) == name) {
      return _parse(service);
    }
  }
  fail('The file holds no service named "$name".');
}

void main() {
  group('the descriptor of a contract', () {
    late Contract contract;

    setUp(() {
      contract = _contract();
    });

    test('holds the file of the contract', () {
      final descriptor = descriptorOf(contract);

      final file = _fileOf(descriptor, 'users.proto');

      expect(_string(file, 2), 'users.v1');
      expect(_string(file, 12), 'proto3');
    });

    test('holds the service and the methods of it', () {
      final descriptor = descriptorOf(contract);

      final service =
          _serviceOf(_fileOf(descriptor, 'users.proto'), 'UsersService');
      final methods = _field(service, 2).cast<List<int>>().toList();

      expect(methods, hasLength(2));
      expect(_name(methods.first), 'GetUser');
      expect(_string(_parse(methods.first), 2), '.users.v1.GetUserRequest');
      expect(_string(_parse(methods.first), 3), '.users.v1.User');
    });

    test('holds the fields of a message with their numbers', () {
      final descriptor = descriptorOf(contract);

      final message = _messageOf(_fileOf(descriptor, 'users.proto'), 'User');
      final fields = _field(message, 2).cast<List<int>>().toList();

      expect(fields, hasLength(5));

      final id = _parse(fields.first);
      expect(_string(id, 1), 'id');
      expect(_field(id, 3).first, 1);
      expect(_field(id, 4).first, 1);
      expect(_field(id, 5).first, 9);
      expect(_string(id, 10), 'id');

      final displayName = _parse(fields[1]);
      expect(_string(displayName, 1), 'display_name');
      expect(_string(displayName, 10), 'displayName');
    });

    test('holds the type of a field with its name', () {
      final descriptor = descriptorOf(contract);

      final message = _messageOf(_fileOf(descriptor, 'users.proto'), 'User');
      final fields = _field(message, 2).cast<List<int>>().toList();

      final role = _parse(fields[2]);
      expect(_field(role, 5).first, 14);
      expect(_string(role, 6), '.users.v1.UserRole');

      final createdAt = _parse(fields[3]);
      expect(_field(createdAt, 5).first, 11);
      expect(_string(createdAt, 6), '.google.protobuf.Timestamp');
    });

    test('holds the file of a well-known type the contract uses', () {
      final descriptor = descriptorOf(contract);

      final timestamp = _fileOf(descriptor, 'google/protobuf/timestamp.proto');

      expect(_string(timestamp, 2), 'google.protobuf');
      expect(
        _name(_field(timestamp, 4).first as List<int>),
        'Timestamp',
      );
    });

    test('holds a message declared inside of a message', () {
      final descriptor = descriptorOf(contract);

      final subscription = _messageOf(
        _fileOf(descriptor, 'users.proto'),
        'Subscription',
      );
      final nested = _field(subscription, 3).cast<List<int>>().toList();

      final plan = nested.firstWhere((message) => _name(message) == 'Plan');
      expect(_name(plan), 'Plan');
    });

    test('holds an enum declared inside of a message', () {
      final descriptor = descriptorOf(contract);

      final subscription = _messageOf(
        _fileOf(descriptor, 'users.proto'),
        'Subscription',
      );
      final enums = _field(subscription, 4).cast<List<int>>().toList();

      expect(enums, hasLength(1));
      expect(_name(enums.first), 'State');
    });

    test('holds a map as a repeated message with an entry of its own', () {
      final descriptor = descriptorOf(contract);

      final subscription = _messageOf(
        _fileOf(descriptor, 'users.proto'),
        'Subscription',
      );
      final fields = _field(subscription, 2).cast<List<int>>().toList();

      final features = _parse(fields.firstWhere((field) {
        final parsed = _parse(field);
        return _string(parsed, 1) == 'features';
      }));

      expect(_field(features, 4).first, 3);
      expect(_field(features, 5).first, 11);
      expect(_string(features, 6), '.users.v1.Subscription.FeaturesEntry');

      final entries = _field(subscription, 3).cast<List<int>>().toList();
      final entry = entries.firstWhere((message) {
        return _name(message) == 'FeaturesEntry';
      });
      final options = _field(_parse(entry), 7).first as List<int>;
      expect(_field(_parse(options), 7).first, 1);
    });

    test('holds the group of a oneof', () {
      final descriptor = descriptorOf(contract);

      final subscription = _messageOf(
        _fileOf(descriptor, 'users.proto'),
        'Subscription',
      );
      final groups = _field(subscription, 8).cast<List<int>>().toList();

      expect(groups, hasLength(1));
      expect(_name(groups.first), 'payment');

      final fields = _field(subscription, 2).cast<List<int>>().toList();
      final members = fields.where((field) {
        final parsed = _parse(field);
        final index = _field(parsed, 9);
        return index.isNotEmpty && index.first == 0;
      }).toList();

      expect(members, hasLength(2));
    });

    test('holds a field that tracks its presence in a group of its own', () {
      final descriptor = descriptorOf(contract);

      final message = _messageOf(_fileOf(descriptor, 'users.proto'), 'User');
      final groups = _field(message, 8).cast<List<int>>().toList();

      expect(groups, hasLength(1));
      expect(_name(groups.first), '_nickname');

      final fields = _field(message, 2).cast<List<int>>().toList();
      final nickname = fields.firstWhere((field) {
        return _string(_parse(field), 1) == 'nickname';
      });
      final parsed = _parse(nickname);

      expect(_field(parsed, 17).first, 1);
      expect(_field(parsed, 9).first, 0);
    });

    test('holds the file of the contract and the files it depends on', () {
      final file = _fileOf(descriptorOf(contract), 'users.proto');

      expect(
        _strings(file, 3),
        contains('google/protobuf/timestamp.proto'),
      );
    });
  });
}
