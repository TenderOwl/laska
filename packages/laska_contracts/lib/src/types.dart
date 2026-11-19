import 'model.dart';

/// Dart type information of a contract type.
class DartType {
  /// Creates a type description.
  DartType({
    required this.dartType,
    required this.protoType,
    this.isMessage = false,
    this.isEnum = false,
    this.messageName,
    this.enumName,
    this.isMap = false,
    this.mapKeyType,
    this.mapValue,
  });

  /// The Dart type as it is written in generated code, e.g. `List<String>`.
  final String dartType;

  /// The type as written in the contract.
  final String protoType;

  /// Whether the type refers to a message.
  final bool isMessage;

  /// Whether the type refers to an enum.
  final bool isEnum;

  /// Name of the Dart class of the referenced message.
  final String? messageName;

  /// Name of the Dart enum of the referenced enum.
  final String? enumName;

  /// Whether the type is a map.
  final bool isMap;

  /// The type of the key of a map, as it is written in the contract.
  final String? mapKeyType;

  /// The type of the value of a map.
  final DartType? mapValue;
}

/// The scalar types of proto3 and their Dart counterparts.
const Map<String, String> scalarTypes = <String, String>{
  'string': 'String',
  'bytes': 'List<int>',
  'bool': 'bool',
  'int32': 'int',
  'int64': 'int',
  'uint32': 'int',
  'uint64': 'int',
  'sint32': 'int',
  'sint64': 'int',
  'fixed32': 'int',
  'fixed64': 'int',
  'sfixed32': 'int',
  'sfixed64': 'int',
  'float': 'double',
  'double': 'double',
};

/// The types a key of a map may have, and their Dart counterparts.
///
/// Protobuf allows the integer types, `bool` and `string` as the key of a map.
const Map<String, String> mapKeyTypes = <String, String>{
  'string': 'String',
  'bool': 'bool',
  'int32': 'int',
  'int64': 'int',
  'uint32': 'int',
  'uint64': 'int',
  'sint32': 'int',
  'sint64': 'int',
  'fixed32': 'int',
  'fixed64': 'int',
  'sfixed32': 'int',
  'sfixed64': 'int',
};

/// Resolves contract types to Dart types.
class TypeResolver {
  /// Creates a resolver for [contract].
  TypeResolver(this.contract);

  /// The contract types are resolved against.
  final Contract contract;

  /// Resolves the type of [field].
  DartType resolve(Field field) {
    if (field.isMap) {
      return _resolveMap(field);
    }

    final type = resolveTypeName(field.type);
    if (!field.repeated) {
      return type;
    }

    return DartType(
      dartType: 'List<${type.dartType}>',
      protoType: type.protoType,
      isMessage: type.isMessage,
      isEnum: type.isEnum,
      messageName: type.messageName,
      enumName: type.enumName,
    );
  }

  /// Resolves the type of the name [name], as it is written in a contract.
  ///
  /// The name may be a scalar, a message or an enum, and it may be qualified
  /// with the scope it was declared in.
  DartType resolveTypeName(String name) {
    final scalar = scalarTypes[name];
    if (scalar != null) {
      return DartType(dartType: scalar, protoType: name);
    }

    final message = _findMessage(name);
    if (message != null) {
      return DartType(
        dartType: message.dartName,
        protoType: name,
        isMessage: true,
        messageName: message.dartName,
      );
    }

    final enumType = _findEnum(name);
    if (enumType != null) {
      return DartType(
        dartType: enumType.dartName,
        protoType: name,
        isEnum: true,
        enumName: enumType.dartName,
      );
    }

    throw StateError('Unknown contract type "$name"');
  }

  /// Finds the message a type reference points to.
  Message? findMessage(String reference) => _findMessage(reference);

  /// Finds the enum a type reference points to.
  EnumType? findEnum(String reference) => _findEnum(reference);

  /// Resolves the type of a map field.
  DartType _resolveMap(Field field) {
    final key = mapKeyTypes[field.mapKeyType];
    if (key == null) {
      throw StateError(
        'Unknown type of the key of the map "${field.name}": '
        '"${field.mapKeyType}"',
      );
    }

    final value = resolveTypeName(field.mapValueType!);

    return DartType(
      dartType: 'Map<$key, ${value.dartType}>',
      protoType: 'map',
      isMap: true,
      mapKeyType: field.mapKeyType,
      mapValue: value,
    );
  }

  Message? _findMessage(String reference) {
    final byFullName = contract.message(reference);
    if (byFullName != null) {
      return byFullName;
    }
    return contract.messageBySimpleName(reference.split('.').last);
  }

  EnumType? _findEnum(String reference) {
    final byFullName = contract.enumType(reference);
    if (byFullName != null) {
      return byFullName;
    }
    return contract.enumBySimpleName(reference.split('.').last);
  }
}
