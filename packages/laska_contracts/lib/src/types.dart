import 'model.dart';
import 'naming.dart';

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
}

/// The scalar types of proto3 and their Dart counterparts.
const Map<String, String> scalarTypes = <String, String>{
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
  'float': 'double',
  'double': 'double',
};

/// Resolves contract types to Dart types.
class TypeResolver {
  /// Creates a resolver for [contract].
  TypeResolver(this.contract);

  /// The contract types are resolved against.
  final Contract contract;

  /// Resolves the type of [field].
  DartType resolve(Field field) {
    final scalar = scalarTypes[field.type];
    if (scalar != null) {
      return DartType(
        dartType: field.repeated ? 'List<$scalar>' : scalar,
        protoType: field.type,
      );
    }

    final message = _findMessage(field.type);
    if (message != null) {
      final name = pascalCase(message.name);
      return DartType(
        dartType: field.repeated ? 'List<$name>' : name,
        protoType: field.type,
        isMessage: true,
        messageName: name,
      );
    }

    final enumType = _findEnum(field.type);
    if (enumType != null) {
      final name = pascalCase(enumType.name);
      return DartType(
        dartType: field.repeated ? 'List<$name>' : name,
        protoType: field.type,
        isEnum: true,
        enumName: name,
      );
    }

    throw StateError('Unknown contract type "${field.type}"');
  }

  /// Finds the message a type reference points to.
  Message? findMessage(String reference) => _findMessage(reference);

  /// Finds the enum a type reference points to.
  EnumType? findEnum(String reference) => _findEnum(reference);

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
