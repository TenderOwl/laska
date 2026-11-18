/// The in-memory model of a parsed contract.
///
/// The model is deliberately close to the `.proto` surface it comes from: it
/// keeps the wire-level facts (field numbers, labels, enum values) that a
/// breaking-change check needs, and nothing that only matters for code
/// generation.
library;

/// A single `.proto` file.
class ProtoFile {
  /// Creates a file model.
  ProtoFile({
    required this.path,
    required this.package,
    required this.messages,
    required this.enums,
    required this.services,
    required this.imports,
  });

  /// Path of the file the model was parsed from.
  final String path;

  /// Protobuf package of the file, e.g. `users.v1`.
  final String package;

  /// Messages declared in the file.
  final List<Message> messages;

  /// Enums declared in the file.
  final List<EnumType> enums;

  /// Services declared in the file.
  final List<Service> services;

  /// Imports found in the file. They are recorded but not resolved.
  final List<String> imports;

  /// Fully qualified name of a message of this file.
  String qualify(String name) => package.isEmpty ? name : '$package.$name';
}

/// The whole contract: every parsed file.
class Contract {
  /// Creates a contract out of [files].
  Contract(this.files);

  /// Parsed files.
  final List<ProtoFile> files;

  /// Every message of every file.
  Iterable<Message> get messages => files.expand((file) => file.messages);

  /// Every enum of every file.
  Iterable<EnumType> get enums => files.expand((file) => file.enums);

  /// Every service of every file.
  Iterable<Service> get services => files.expand((file) => file.services);

  /// Finds a message by its fully qualified name.
  Message? message(String fullName) {
    for (final message in messages) {
      if (message.fullName == fullName) {
        return message;
      }
    }
    return null;
  }

  /// Finds an enum by its fully qualified name.
  EnumType? enumType(String fullName) {
    for (final value in enums) {
      if (value.fullName == fullName) {
        return value;
      }
    }
    return null;
  }

  /// Finds a message by its simple name.
  ///
  /// Used to resolve type references written without a package qualifier.
  Message? messageBySimpleName(String name) {
    for (final message in messages) {
      if (message.name == name) {
        return message;
      }
    }
    return null;
  }

  /// Finds an enum by its simple name.
  EnumType? enumBySimpleName(String name) {
    for (final value in enums) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }
}

/// A message declaration.
class Message {
  /// Creates a message model.
  Message({
    required this.name,
    required this.fields,
    this.comment,
    this.package = '',
  });

  /// Simple name of the message.
  final String name;

  /// Fields of the message.
  final List<Field> fields;

  /// Leading documentation comment, if any.
  final String? comment;

  /// Protobuf package the message belongs to.
  final String package;

  /// Fully qualified name of the message.
  String get fullName => package.isEmpty ? name : '$package.$name';

  /// Finds a field by its proto name.
  Field? field(String fieldName) {
    for (final value in fields) {
      if (value.name == fieldName) {
        return value;
      }
    }
    return null;
  }
}

/// A field of a message.
class Field {
  /// Creates a field model.
  Field({
    required this.name,
    required this.number,
    required this.type,
    this.repeated = false,
    this.optional = false,
    this.comment,
  });

  /// Proto name of the field, e.g. `display_name`.
  final String name;

  /// Field number on the wire.
  final int number;

  /// Type as written in the contract, e.g. `string` or `users.v1.User`.
  final String type;

  /// Whether the field is a repeated field.
  final bool repeated;

  /// Whether the field explicitly tracks presence (`optional`).
  final bool optional;

  /// Leading documentation comment, if any.
  final String? comment;

  /// Whether the field tracks presence explicitly.
  bool get hasPresence => optional;
}

/// An enum declaration.
class EnumType {
  /// Creates an enum model.
  EnumType({
    required this.name,
    required this.values,
    this.comment,
    this.package = '',
  });

  /// Simple name of the enum.
  final String name;

  /// Values of the enum.
  final List<EnumValue> values;

  /// Leading documentation comment, if any.
  final String? comment;

  /// Protobuf package the enum belongs to.
  final String package;

  /// Fully qualified name of the enum.
  String get fullName => package.isEmpty ? name : '$package.$name';
}

/// A single value of an enum.
class EnumValue {
  /// Creates an enum value model.
  EnumValue({
    required this.name,
    required this.number,
    this.comment,
  });

  /// Proto name of the value, e.g. `USER_ROLE_ADMIN`.
  final String name;

  /// Number of the value.
  final int number;

  /// Leading documentation comment, if any.
  final String? comment;
}

/// A service declaration.
class Service {
  /// Creates a service model.
  Service({
    required this.name,
    required this.methods,
    this.comment,
    this.package = '',
    this.policy,
  });

  /// Simple name of the service.
  final String name;

  /// Methods of the service.
  final List<Method> methods;

  /// Leading documentation comment, if any.
  final String? comment;

  /// Protobuf package the service belongs to.
  final String package;

  /// The policy of the service, applied to every method that has none.
  ///
  /// It comes from the `laska.policy` annotation of the service.
  final MethodPolicy? policy;

  /// Fully qualified name of the service.
  String get fullName => package.isEmpty ? name : '$package.$name';
}

/// The policy of a method, as it is written in the contract.
///
/// The policy is what makes the resilience of a call visible in the contract
/// instead of hidden in the code of the caller: the timeout, the retry and the
/// idempotency of a method are declared next to its signature.
class MethodPolicy {
  /// Creates a policy.
  MethodPolicy({
    this.timeout,
    this.maxAttempts,
    this.backoff,
    this.maxBackoff,
    this.jitter,
    this.idempotent,
  });

  /// How long one attempt of the call may take.
  final Duration? timeout;

  /// How many times the call is made in total.
  final int? maxAttempts;

  /// The backoff before the second attempt.
  final Duration? backoff;

  /// The longest wait between two attempts.
  final Duration? maxBackoff;

  /// Whether the wait between two attempts is randomised.
  final bool? jitter;

  /// Whether the call may be repeated.
  final bool? idempotent;

  /// A copy of this policy with the fields of [other] on top of it.
  ///
  /// The fields of [other] win, so the policy of a method wins over the policy
  /// of the service.
  MethodPolicy merge(MethodPolicy? other) {
    if (other == null) {
      return this;
    }
    return MethodPolicy(
      timeout: other.timeout ?? timeout,
      maxAttempts: other.maxAttempts ?? maxAttempts,
      backoff: other.backoff ?? backoff,
      maxBackoff: other.maxBackoff ?? maxBackoff,
      jitter: other.jitter ?? jitter,
      idempotent: other.idempotent ?? idempotent,
    );
  }

  /// Whether the policy holds nothing.
  bool get isEmpty =>
      timeout == null &&
      maxAttempts == null &&
      backoff == null &&
      maxBackoff == null &&
      jitter == null &&
      idempotent == null;
}

/// A single RPC of a service.
class Method {
  /// Creates a method model.
  Method({
    required this.name,
    required this.requestType,
    required this.responseType,
    this.httpRules = const <HttpRule>[],
    this.comment,
    this.policy,
  });

  /// Proto name of the method, e.g. `GetUser`.
  final String name;

  /// Type of the request message.
  final String requestType;

  /// Type of the response message.
  final String responseType;

  /// HTTP bindings of the method.
  final List<HttpRule> httpRules;

  /// Leading documentation comment, if any.
  final String? comment;

  /// The policy of the method, when it declares one.
  ///
  /// It comes from the `laska.policy` annotation of the method.
  final MethodPolicy? policy;
}

/// An HTTP binding of a method.
class HttpRule {
  /// Creates an HTTP rule.
  HttpRule({
    required this.method,
    required this.path,
    this.body,
  });

  /// HTTP method, e.g. `GET`.
  final String method;

  /// Path template, e.g. `/v1/users/{id}`.
  final String path;

  /// Name of the request field holding the body, or `*` for the whole message.
  String? body;

  /// Path parameters referenced by the template.
  List<String> get pathParameters {
    final parameters = <String>[];
    for (final match in RegExp(r'\{([^}]+)\}').allMatches(path)) {
      parameters.add(match.group(1)!);
    }
    return parameters;
  }

  @override
  String toString() => '$method $path';
}
