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
  userRoleUnspecified('USER_ROLE_UNSPECIFIED', number: 0),
  userRoleAdmin('USER_ROLE_ADMIN', number: 1),
  userRoleMember('USER_ROLE_MEMBER', number: 2);

  const UserRole(this.protoName, {this.number = 0});

  /// The name of the value in the contract.
  final String protoName;

  /// The number of the value on the wire.
  final int number;

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

  /// Reads the value of the number [number].
  static UserRole fromNumber(int number) {
    for (final value in UserRole.values) {
      if (value.number == number) {
        return value;
      }
    }
    return UserRole.userRoleUnspecified;
  }
}

/// The state of the subscription.
enum SubscriptionState {
  subscriptionStateActive('SUBSCRIPTION_STATE_ACTIVE', number: 0),
  subscriptionStatePaused('SUBSCRIPTION_STATE_PAUSED', number: 1);

  const SubscriptionState(this.protoName, {this.number = 0});

  /// The name of the value in the contract.
  final String protoName;

  /// The number of the value on the wire.
  final int number;

  /// Parses [raw] into a SubscriptionState value.
  static SubscriptionState fromName(Object? raw, {String? field}) {
    if (raw is String) {
      for (final value in SubscriptionState.values) {
        if (value.protoName == raw || value.name == raw) {
          return value;
        }
      }
    }
    if (field != null) {
      throw FormatException('Unknown SubscriptionState value for $field: $raw');
    }
    throw FormatException('Unknown SubscriptionState value: $raw');
  }

  /// Reads the value of the number [number].
  static SubscriptionState fromNumber(int number) {
    for (final value in SubscriptionState.values) {
      if (value.number == number) {
        return value;
      }
    }
    return SubscriptionState.subscriptionStateActive;
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
    required this.createdAt,
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

  /// The moment the account was created.
  final ProtoTimestamp createdAt;

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
    final createdAt = json['createdAt'];
    if (createdAt is! String) {
      throw const FormatException('User.createdAt must be a string');
    }
    final createdAtValue = ProtoTimestamp.fromJson(createdAt);
    return User(
      id: id,
      email: email,
      displayName: displayName,
      role: roleValue,
      tags: tags == null
          ? const <String>[]
          : List<String>.from(tags.map((item) => item as String)),
      createdAt: createdAtValue,
    );
  }

  /// The JSON representation of the User.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'email': email,
        'displayName': displayName,
        'role': role.protoName,
        'tags': tags,
        'createdAt': createdAt.toJson(),
      };

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (id != '') {
      writer.writeString(1, id);
    }
    if (email != '') {
      writer.writeString(2, email);
    }
    if (displayName != '') {
      writer.writeString(3, displayName);
    }
    if (role.number != 0) {
      writer.writeEnum(4, role.number);
    }
    for (final item in tags) {
      writer.writeString(5, item);
    }
    writer.writeMessage(6, createdAt.toProtoBytes());
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory User.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var id = '';
    var email = '';
    var displayName = '';
    var role = UserRole.userRoleUnspecified;
    var tags = <String>[];
    ProtoTimestamp? createdAt;

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          id = reader.readString();
        case 2:
          email = reader.readString();
        case 3:
          displayName = reader.readString();
        case 4:
          role = UserRole.fromNumber(reader.readEnum());
        case 5:
          tags.add(reader.readString());
        case 6:
          createdAt = ProtoTimestamp.fromProtoBytes(reader.readBytes());
        default:
          reader.skipField();
      }
    }

    if (createdAt == null) {
      throw FormatException('The message "User" needs the field "createdAt".');
    }
    return User(
      id: id,
      email: email,
      displayName: displayName,
      role: role,
      tags: tags,
      createdAt: createdAt,
    );
  }
}

/// Request of the GetUser method.
class GetUserRequest {
  /// Creates a GetUserRequest.
  const GetUserRequest({
    required this.id,
  });

  final String id;

  /// Builds a GetUserRequest from its JSON representation.
  factory GetUserRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('GetUserRequest.id must be of type String');
    }
    return GetUserRequest(
      id: id,
    );
  }

  /// The JSON representation of the GetUserRequest.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
      };

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (id != '') {
      writer.writeString(1, id);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory GetUserRequest.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var id = '';

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          id = reader.readString();
        default:
          reader.skipField();
      }
    }

    return GetUserRequest(
      id: id,
    );
  }
}

/// Request of the ListUsers method.
class ListUsersRequest {
  /// Creates a ListUsersRequest.
  const ListUsersRequest({
    required this.limit,
    required this.cursor,
  });

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
          'ListUsersRequest.cursor must be of type String');
    }
    return ListUsersRequest(
      limit: limit,
      cursor: cursor,
    );
  }

  /// The JSON representation of the ListUsersRequest.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'limit': limit,
        'cursor': cursor,
      };

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (limit != 0) {
      writer.writeInt32(1, limit);
    }
    if (cursor != '') {
      writer.writeString(2, cursor);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory ListUsersRequest.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var limit = 0;
    var cursor = '';

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          limit = reader.readInt32();
        case 2:
          cursor = reader.readString();
        default:
          reader.skipField();
      }
    }

    return ListUsersRequest(
      limit: limit,
      cursor: cursor,
    );
  }
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
            users.map((item) => User.fromJson(item as Map<String, dynamic>)));
    final nextCursor = json['nextCursor'];
    if (nextCursor is! String) {
      throw const FormatException(
          'ListUsersResponse.nextCursor must be of type String');
    }
    return ListUsersResponse(
      users: usersValue,
      nextCursor: nextCursor,
    );
  }

  /// The JSON representation of the ListUsersResponse.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'users': users.map((item) => item.toJson()).toList(),
        'nextCursor': nextCursor,
      };

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    for (final item in users) {
      writer.writeMessage(1, item.toProtoBytes());
    }
    if (nextCursor != '') {
      writer.writeString(2, nextCursor);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory ListUsersResponse.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var users = <User>[];
    var nextCursor = '';

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          users.add(User.fromProtoBytes(reader.readBytes()));
        case 2:
          nextCursor = reader.readString();
        default:
          reader.skipField();
      }
    }

    return ListUsersResponse(
      users: users,
      nextCursor: nextCursor,
    );
  }
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
          'CreateUserRequest.email must be of type String');
    }
    final displayName = json['displayName'];
    if (displayName is! String) {
      throw const FormatException(
          'CreateUserRequest.displayName must be of type String');
    }
    final roleValue =
        UserRole.fromName(json['role'], field: 'CreateUserRequest.role');
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

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (email != '') {
      writer.writeString(1, email);
    }
    if (displayName != '') {
      writer.writeString(2, displayName);
    }
    if (role.number != 0) {
      writer.writeEnum(3, role.number);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory CreateUserRequest.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var email = '';
    var displayName = '';
    var role = UserRole.userRoleUnspecified;

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          email = reader.readString();
        case 2:
          displayName = reader.readString();
        case 3:
          role = UserRole.fromNumber(reader.readEnum());
        default:
          reader.skipField();
      }
    }

    return CreateUserRequest(
      email: email,
      displayName: displayName,
      role: role,
    );
  }
}

/// A subscription of a user to a plan.
/// The message holds the constructs a contract needs the most: a message
/// declared inside a message, an enum declared inside a message, a map and a
/// group of a oneof.
class Subscription {
  /// Creates a Subscription.
  const Subscription({
    required this.plan,
    required this.state,
    this.features = const <String, bool>{},
    this.payment,
  });

  /// The plan of the subscription.
  final SubscriptionPlan plan;

  /// The state of the subscription.
  final SubscriptionState state;

  /// The features of the plan, by their name.
  final Map<String, bool> features;

  /// The group of the oneof `payment`.
  ///
  /// Only one member of the group carries a value.
  final SubscriptionPayment? payment;

  /// Builds a Subscription from its JSON representation.
  factory Subscription.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'];
    if (plan is! Map<String, dynamic>) {
      throw const FormatException('Subscription.plan must be an object');
    }
    final planValue = SubscriptionPlan.fromJson(plan);
    final stateValue =
        SubscriptionState.fromName(json['state'], field: 'Subscription.state');
    final features = json['features'];
    if (features != null && features is! Map) {
      throw const FormatException('Subscription.features must be an object');
    }
    final featuresValue = <String, bool>{};
    if (features != null) {
      features.forEach((mapKey, mapValue) {
        featuresValue[mapKey as String] = mapValue as bool;
      });
    }
    return Subscription(
      plan: planValue,
      state: stateValue,
      features: featuresValue,
      payment: SubscriptionPayment.fromJson(json),
    );
  }

  /// The JSON representation of the Subscription.
  Map<String, dynamic> toJson() {
    final paymentValue = payment;
    return <String, dynamic>{
      'plan': plan.toJson(),
      'state': state.protoName,
      'features': features,
      if (paymentValue != null) ...paymentValue.toJson(),
    };
  }

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    final paymentValue = payment;
    writer.writeMessage(1, plan.toProtoBytes());
    if (state.number != 0) {
      writer.writeEnum(2, state.number);
    }
    for (final entry in features.entries) {
      final entryWriter = ProtoWriter();
      entryWriter.writeString(1, entry.key);
      entryWriter.writeBool(2, entry.value);
      writer.writeMessage(3, entryWriter.toBytes());
    }
    if (paymentValue is SubscriptionPaymentCardToken) {
      writer.writeString(4, paymentValue.value);
    }
    if (paymentValue is SubscriptionPaymentIban) {
      writer.writeString(5, paymentValue.value);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory Subscription.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    SubscriptionPlan? plan;
    var state = SubscriptionState.subscriptionStateActive;
    var features = <String, bool>{};
    SubscriptionPayment? payment;

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          plan = SubscriptionPlan.fromProtoBytes(reader.readBytes());
        case 2:
          state = SubscriptionState.fromNumber(reader.readEnum());
        case 3:
          final entryReader = ProtoReader(reader.readBytes());
          var mapEntryKeyFeatures = '';
          var mapEntryValueFeatures = false;
          while (entryReader.hasNext) {
            final entryTag = entryReader.readTag();
            switch (entryTag) {
              case 1:
                mapEntryKeyFeatures = entryReader.readString();
              case 2:
                mapEntryValueFeatures = entryReader.readBool();
              default:
                entryReader.skipField();
            }
          }
          features[mapEntryKeyFeatures] = mapEntryValueFeatures;
        case 4:
          payment = SubscriptionPaymentCardToken(reader.readString());
        case 5:
          payment = SubscriptionPaymentIban(reader.readString());
        default:
          reader.skipField();
      }
    }

    if (plan == null) {
      throw FormatException(
          'The message "Subscription" needs the field "plan".');
    }
    return Subscription(
      plan: plan,
      state: state,
      features: features,
      payment: payment,
    );
  }
}

/// The group of the oneof `payment` of the `Subscription` message.
///
/// The members of the group are exclusive: only one of them
/// carries a value.
sealed class SubscriptionPayment {
  const SubscriptionPayment();

  /// The name of the member of the group that is set.
  String get memberName;

  /// The JSON representation of the member that is set.
  Map<String, dynamic> toJson();

  /// Reads the group out of the JSON of a message.
  ///
  /// Returns `null` when no member of the group is set.
  static SubscriptionPayment? fromJson(Map<String, dynamic> json) {
    if (json.containsKey('cardToken')) {
      final value = json['cardToken'];
      if (value is! String) {
        throw const FormatException(
            'Subscription.payment.cardToken must be of type String');
      }
      return SubscriptionPaymentCardToken(value);
    }
    if (json.containsKey('iban')) {
      final value = json['iban'];
      if (value is! String) {
        throw const FormatException(
            'Subscription.payment.iban must be of type String');
      }
      return SubscriptionPaymentIban(value);
    }
    return null;
  }
}

/// The member `cardToken` of the group `payment` of the `Subscription` message.
class SubscriptionPaymentCardToken extends SubscriptionPayment {
  const SubscriptionPaymentCardToken(this.value);

  /// The value of the member.
  final String value;

  @override
  String get memberName => 'cardToken';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'cardToken': value,
      };
}

/// The member `iban` of the group `payment` of the `Subscription` message.
class SubscriptionPaymentIban extends SubscriptionPayment {
  const SubscriptionPaymentIban(this.value);

  /// The value of the member.
  final String value;

  @override
  String get memberName => 'iban';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'iban': value,
      };
}

/// The plan of the subscription.
class SubscriptionPlan {
  /// Creates a SubscriptionPlan.
  const SubscriptionPlan({
    required this.name,
    required this.seats,
  });

  final String name;
  final int seats;

  /// Builds a SubscriptionPlan from its JSON representation.
  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String) {
      throw const FormatException(
          'SubscriptionPlan.name must be of type String');
    }
    final seats = json['seats'];
    if (seats is! int) {
      throw const FormatException('SubscriptionPlan.seats must be of type int');
    }
    return SubscriptionPlan(
      name: name,
      seats: seats,
    );
  }

  /// The JSON representation of the SubscriptionPlan.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'seats': seats,
      };

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (name != '') {
      writer.writeString(1, name);
    }
    if (seats != 0) {
      writer.writeInt32(2, seats);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory SubscriptionPlan.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var name = '';
    var seats = 0;

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          name = reader.readString();
        case 2:
          seats = reader.readInt32();
        default:
          reader.skipField();
      }
    }

    return SubscriptionPlan(
      name: name,
      seats: seats,
    );
  }
}

// Service UsersService

/// UsersService manages the accounts of the application.
abstract class UsersService {
  /// GetUser returns a single user by its identifier.
  Future<User> getUser(GetUserRequest request);

  /// ListUsers returns a page of users.
  Future<ListUsersResponse> listUsers(ListUsersRequest request);

  /// CreateUser creates a new user.
  /// The call changes something, so it is never retried.
  Future<User> createUser(CreateUserRequest request);
}

/// Registers the REST projection of [service] on [app].
void registerUsersService(
  Laska app,
  UsersService service, {
  List<Middleware> middleware = const <Middleware>[],
}) {
  app.get(
    '/v1/users/:id',
    (ctx) async {
      final payload = <String, dynamic>{};
      payload['id'] = ctx.params['id']!;
      final request = GetUserRequest.fromJson(payload);
      final response = await service.getUser(request);
      return ctx.json(response.toJson());
    },
    middleware: middleware,
  );

  app.get(
    '/v1/users',
    (ctx) async {
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
    },
    middleware: middleware,
  );

  app.post(
    '/v1/users',
    (ctx) async {
      final payload = <String, dynamic>{};
      payload.addAll(ctx.request.json());
      final request = CreateUserRequest.fromJson(payload);
      final response = await service.createUser(request);
      return ctx.json(response.toJson());
    },
    middleware: middleware,
  );
}

/// The policies of the methods of the `UsersService` service.
///
/// The policies come from the `laska.policy` annotations of the
/// contract, so the way a method is called is visible in the
/// contract itself and not only in the code of the caller.
class UsersServicePolicies {
  const UsersServicePolicies._();

  /// The policy of the `GetUser` method.
  static final DependencyPolicy getUser = DependencyPolicy(
      timeout: Duration(seconds: 2),
      retry: RetryPolicy(
          maxAttempts: 3,
          initialBackoff: Duration(milliseconds: 100),
          maxBackoff: Duration(seconds: 2),
          jitter: true),
      idempotent: true);

  /// The policy of the `ListUsers` method.
  static final DependencyPolicy listUsers = DependencyPolicy(
      timeout: Duration(seconds: 2),
      retry: RetryPolicy(
          maxAttempts: 3,
          initialBackoff: Duration(milliseconds: 100),
          maxBackoff: Duration(seconds: 2),
          jitter: true),
      idempotent: true);

  /// The policy of the `CreateUser` method.
  static final DependencyPolicy createUser = DependencyPolicy(
      timeout: Duration(seconds: 2),
      retry: RetryPolicy(
          maxAttempts: 3,
          initialBackoff: Duration(milliseconds: 100),
          maxBackoff: Duration(seconds: 2),
          jitter: true));

  /// The policies of the methods, by the name of the method.
  static final Map<String, DependencyPolicy> policies =
      <String, DependencyPolicy>{
    'GetUser': getUser,
    'ListUsers': listUsers,
    'CreateUser': createUser,
  };
}

/// Typed client for the `UsersService` service.
class UsersServiceClient {
  /// Creates a client talking to [baseUrl].
  UsersServiceClient({
    required this.baseUrl,
    ServiceTransport? transport,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 2),
    Tracer? tracer,
    String dependencyName = 'UsersService',
    DependencyPolicy policy = const DependencyPolicy(),
    Map<String, DependencyPolicy>? policies,
  })  : _transport = transport ??
            HttpServiceTransport(baseUrl: baseUrl, client: httpClient),
        // ignore: prefer_initializing_formals
        _timeout = timeout,
        // ignore: prefer_initializing_formals
        _tracer = tracer,
        // ignore: prefer_initializing_formals
        _dependencyName = dependencyName,
        // ignore: prefer_initializing_formals
        _policy = policy,
        // ignore: prefer_initializing_formals
        _policies = <String, DependencyPolicy>{
          ...UsersServicePolicies.policies,
          ...?policies,
        };

  /// Base URL of the service, e.g. `http://localhost:8080`.
  final String baseUrl;

  /// The transport the calls go through.
  final ServiceTransport _transport;

  /// The timeout of the calls that have no policy of their own.
  final Duration _timeout;

  /// The tracer of the client, when the calls are traced.
  final Tracer? _tracer;

  /// The name of the dependency the calls go to.
  final String _dependencyName;

  /// The policy of the dependency.
  ///
  /// It holds the circuit breaker and the bulkhead of the
  /// dependency, which every call of the client shares.
  final DependencyPolicy _policy;

  /// The policy of every method, by the name of the method.
  final Map<String, DependencyPolicy> _policies;

  /// The dependency the calls go through.
  ///
  /// The dependency holds the circuit breaker and the bulkhead
  /// of the service, so every call of the client shares them.
  late final Dependency _dependency = Dependency(
    name: _dependencyName,
    transport: _transport,
    policy: _policy,
    tracer: _tracer,
  );

  /// GetUser returns a single user by its identifier.
  Future<User> getUser(GetUserRequest request, {String? idempotencyKey}) async {
    final uri = _transport.buildUri(
      '/v1/users/${Uri.encodeComponent(request.id.toString())}',
      '/users.v1.UsersService/GetUser',
    );

    final headers = <String, String>{
      'accept': 'application/json',
    };

    if (idempotencyKey != null) {
      headers['idempotency-key'] = idempotencyKey;
    }

    final body = null;

    final response = await _send(
      'GetUser',
      'UsersService.GetUser',
      'get',
      uri,
      headers,
      body,
    );

    return _transport.bodyFormat == BodyFormat.protobuf
        ? User.fromProtoBytes(response.body)
        : User.fromJson(jsonDecode(response.text) as Map<String, dynamic>);
  }

  /// ListUsers returns a page of users.
  Future<ListUsersResponse> listUsers(ListUsersRequest request,
      {String? idempotencyKey}) async {
    final query = <String, String>{};
    query['limit'] = request.limit.toString();
    query['cursor'] = request.cursor.toString();

    final uri = _transport
        .buildUri(
          '/v1/users',
          '/users.v1.UsersService/ListUsers',
        )
        .replace(
          queryParameters: query.isEmpty ? null : query,
        );

    final headers = <String, String>{
      'accept': 'application/json',
    };

    if (idempotencyKey != null) {
      headers['idempotency-key'] = idempotencyKey;
    }

    final body = null;

    final response = await _send(
      'ListUsers',
      'UsersService.ListUsers',
      'get',
      uri,
      headers,
      body,
    );

    return _transport.bodyFormat == BodyFormat.protobuf
        ? ListUsersResponse.fromProtoBytes(response.body)
        : ListUsersResponse.fromJson(
            jsonDecode(response.text) as Map<String, dynamic>);
  }

  /// CreateUser creates a new user.
  /// The call changes something, so it is never retried.
  Future<User> createUser(CreateUserRequest request,
      {String? idempotencyKey}) async {
    final uri = _transport.buildUri(
      '/v1/users',
      '/users.v1.UsersService/CreateUser',
    );

    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
    };

    final key = idempotencyKey ?? newIdempotencyKey();
    headers['idempotency-key'] = key;

    final body = _transport.bodyFormat == BodyFormat.protobuf
        ? request.toProtoBytes()
        : utf8.encode(jsonEncode(request.toJson()));

    final response = await _send(
      'CreateUser',
      'UsersService.CreateUser',
      'post',
      uri,
      headers,
      body,
    );

    return _transport.bodyFormat == BodyFormat.protobuf
        ? User.fromProtoBytes(response.body)
        : User.fromJson(jsonDecode(response.text) as Map<String, dynamic>);
  }

  /// Sends the request of a method of the service.
  ///
  /// The policy of the method decides how the call is timed out,
  /// how often it is retried and whether it may be retried at all.
  Future<TransportResponse> _send(
    String method,
    String operation,
    String verb,
    Uri uri,
    Map<String, String> headers,
    List<int>? body,
  ) async {
    final methodPolicy = _policies[method];
    final effectivePolicy = methodPolicy == null
        ? DependencyPolicy(timeout: _timeout)
        : methodPolicy.copyWith(
            timeout: methodPolicy.timeout ?? _timeout,
          );
    try {
      return await _dependency.call(
        TransportRequest(
          method: verb,
          uri: uri,
          headers: headers,
          body: body,
          contentType: body == null
              ? null
              : _transport.bodyFormat == BodyFormat.protobuf
                  ? "application/protobuf"
                  : "application/json",
        ),
        policy: effectivePolicy,
        operation: operation,
        attributes: <String, Object?>{
          'http.request.method': verb,
          'url.path': uri.path,
        },
      );
    } on DependencyFailure catch (error) {
      throw LaskaApiException(error.statusCode ?? 502, error.body);
    } on DependencyTimeoutException catch (error) {
      throw LaskaApiException(504, error.toString());
    } on CircuitOpenException catch (error) {
      throw LaskaApiException(503, error.toString());
    } on BulkheadFullException catch (error) {
      throw LaskaApiException(503, error.toString());
    }
  }
}
