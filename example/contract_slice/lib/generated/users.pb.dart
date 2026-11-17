// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Source: users.proto
// Regenerate with: laska contract compile

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:laska_core/laska_core.dart';

// Enums

/// The role a user has.
enum UserRole {
  userRoleUnspecified('USER_ROLE_UNSPECIFIED'),
  userRoleAdmin('USER_ROLE_ADMIN'),
  userRoleMember('USER_ROLE_MEMBER');

  const UserRole(this.protoName);

  /// The name of the value in the contract.
  final String protoName;

  /// Parses [raw] into a UserRole value.
  static UserRole fromName(Object? raw, {String? field}) {
    if (raw is String) {
      for (final value in UserRole.values) {
        if (value.protoName == raw || value.name == raw) {
          return value;
        }
      }
    }
    if (field != null) {
      throw FormatException('Unknown UserRole value for $field: $raw');
    }
    throw FormatException('Unknown UserRole value: $raw');
  }
}

// Messages

/// A user of the application.
class User {
  /// Creates a User.
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.tags = const <String>[],
  });

  /// Stable identifier of the user.
  final String id;

  /// Email address of the user.
  final String email;

  /// Human readable name.
  final String displayName;

  /// Role of the user.
  final UserRole role;

  /// Free form tags.
  final List<String> tags;

  /// Builds a User from its JSON representation.
  factory User.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('User.id must be of type String');
    }
    final email = json['email'];
    if (email is! String) {
      throw const FormatException('User.email must be of type String');
    }
    final displayName = json['displayName'];
    if (displayName is! String) {
      throw const FormatException('User.displayName must be of type String');
    }
    final roleValue = UserRole.fromName(json['role'], field: 'User.role');
    final tags = json['tags'];
    if (tags != null && tags is! List) {
      throw const FormatException('User.tags must be a list');
    }
    return User(
      id: id,
      email: email,
      displayName: displayName,
      role: roleValue,
      tags: tags == null
          ? const <String>[]
          : List<String>.from(tags.map((item) => item as String)),
    );
  }

  /// The JSON representation of the User.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'email': email,
    'displayName': displayName,
    'role': role.protoName,
    'tags': tags,
  };
}

/// Request of the GetUser method.
class GetUserRequest {
  /// Creates a GetUserRequest.
  const GetUserRequest({required this.id});

  final String id;

  /// Builds a GetUserRequest from its JSON representation.
  factory GetUserRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('GetUserRequest.id must be of type String');
    }
    return GetUserRequest(id: id);
  }

  /// The JSON representation of the GetUserRequest.
  Map<String, dynamic> toJson() => <String, dynamic>{'id': id};
}

/// Request of the ListUsers method.
class ListUsersRequest {
  /// Creates a ListUsersRequest.
  const ListUsersRequest({required this.limit, required this.cursor});

  final int limit;
  final String cursor;

  /// Builds a ListUsersRequest from its JSON representation.
  factory ListUsersRequest.fromJson(Map<String, dynamic> json) {
    final limit = json['limit'];
    if (limit is! int) {
      throw const FormatException('ListUsersRequest.limit must be of type int');
    }
    final cursor = json['cursor'];
    if (cursor is! String) {
      throw const FormatException(
        'ListUsersRequest.cursor must be of type String',
      );
    }
    return ListUsersRequest(limit: limit, cursor: cursor);
  }

  /// The JSON representation of the ListUsersRequest.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'limit': limit,
    'cursor': cursor,
  };
}

/// Response of the ListUsers method.
class ListUsersResponse {
  /// Creates a ListUsersResponse.
  const ListUsersResponse({
    this.users = const <User>[],
    required this.nextCursor,
  });

  final List<User> users;
  final String nextCursor;

  /// Builds a ListUsersResponse from its JSON representation.
  factory ListUsersResponse.fromJson(Map<String, dynamic> json) {
    final users = json['users'];
    if (users != null && users is! List) {
      throw const FormatException('ListUsersResponse.users must be a list');
    }
    final usersValue = users == null
        ? const <User>[]
        : List<User>.from(
            users.map((item) => User.fromJson(item as Map<String, dynamic>)),
          );
    final nextCursor = json['nextCursor'];
    if (nextCursor is! String) {
      throw const FormatException(
        'ListUsersResponse.nextCursor must be of type String',
      );
    }
    return ListUsersResponse(users: usersValue, nextCursor: nextCursor);
  }

  /// The JSON representation of the ListUsersResponse.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'users': users.map((item) => item.toJson()).toList(),
    'nextCursor': nextCursor,
  };
}

/// Request of the CreateUser method.
class CreateUserRequest {
  /// Creates a CreateUserRequest.
  const CreateUserRequest({
    required this.email,
    required this.displayName,
    required this.role,
  });

  final String email;
  final String displayName;
  final UserRole role;

  /// Builds a CreateUserRequest from its JSON representation.
  factory CreateUserRequest.fromJson(Map<String, dynamic> json) {
    final email = json['email'];
    if (email is! String) {
      throw const FormatException(
        'CreateUserRequest.email must be of type String',
      );
    }
    final displayName = json['displayName'];
    if (displayName is! String) {
      throw const FormatException(
        'CreateUserRequest.displayName must be of type String',
      );
    }
    final roleValue = UserRole.fromName(
      json['role'],
      field: 'CreateUserRequest.role',
    );
    return CreateUserRequest(
      email: email,
      displayName: displayName,
      role: roleValue,
    );
  }

  /// The JSON representation of the CreateUserRequest.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'email': email,
    'displayName': displayName,
    'role': role.protoName,
  };
}

// Service UsersService

/// UsersService manages the accounts of the application.
abstract class UsersService {
  /// GetUser returns a single user by its identifier.
  Future<User> getUser(GetUserRequest request);

  /// ListUsers returns a page of users.
  Future<ListUsersResponse> listUsers(ListUsersRequest request);

  /// CreateUser creates a new user.
  Future<User> createUser(CreateUserRequest request);
}

/// Registers the REST projection of [service] on [app].
void registerUsersService(
  Laska app,
  UsersService service, {
  List<Middleware> middleware = const <Middleware>[],
}) {
  app.get('/v1/users/:id', (ctx) async {
    final payload = <String, dynamic>{};
    payload['id'] = ctx.params['id']!;
    final request = GetUserRequest.fromJson(payload);
    final response = await service.getUser(request);
    return ctx.json(response.toJson());
  }, middleware: middleware);

  app.get('/v1/users', (ctx) async {
    final payload = <String, dynamic>{};
    final query = ctx.query;
    if (query.containsKey('limit')) {
      payload['limit'] = parseIntValue(query['limit']!, 'limit');
    }
    if (query.containsKey('cursor')) {
      payload['cursor'] = query['cursor']!;
    }
    final request = ListUsersRequest.fromJson(payload);
    final response = await service.listUsers(request);
    return ctx.json(response.toJson());
  }, middleware: middleware);

  app.post('/v1/users', (ctx) async {
    final payload = <String, dynamic>{};
    payload.addAll(ctx.request.json());
    final request = CreateUserRequest.fromJson(payload);
    final response = await service.createUser(request);
    return ctx.json(response.toJson());
  }, middleware: middleware);
}

/// Typed client for the `UsersService` service.
class UsersServiceClient {
  /// Creates a client talking to [baseUrl].
  UsersServiceClient({
    required this.baseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 2),
  }) : _http = httpClient ?? http.Client(),
       // ignore: prefer_initializing_formals
       _timeout = timeout;

  /// Base URL of the service, e.g. `http://localhost:8080`.
  final String baseUrl;

  final http.Client _http;
  final Duration _timeout;

  /// GetUser returns a single user by its identifier.
  Future<User> getUser(GetUserRequest request) async {
    final uri = Uri.parse(
      '$baseUrl/v1/users/${Uri.encodeComponent(request.id.toString())}',
    );

    final response = await _http
        .get(uri, headers: const <String, String>{'accept': 'application/json'})
        .timeout(_timeout);
    if (response.statusCode >= 400) {
      throw LaskaApiException(response.statusCode, response.body);
    }
    return User.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// ListUsers returns a page of users.
  Future<ListUsersResponse> listUsers(ListUsersRequest request) async {
    final query = <String, String>{};
    query['limit'] = request.limit.toString();
    query['cursor'] = request.cursor.toString();

    final uri = Uri.parse('$baseUrl/v1/users')
        .replace(queryParameters: query.isEmpty ? null : query);

    final response = await _http
        .get(uri, headers: const <String, String>{'accept': 'application/json'})
        .timeout(_timeout);
    if (response.statusCode >= 400) {
      throw LaskaApiException(response.statusCode, response.body);
    }
    return ListUsersResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// CreateUser creates a new user.
  Future<User> createUser(CreateUserRequest request) async {
    final uri = Uri.parse('$baseUrl/v1/users');

    final response = await _http
        .post(
          uri,
          headers: const <String, String>{
            'accept': 'application/json',
            'content-type': 'application/json',
          },
          body: jsonEncode(request.toJson()),
        )
        .timeout(_timeout);
    if (response.statusCode >= 400) {
      throw LaskaApiException(response.statusCode, response.body);
    }
    return User.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
