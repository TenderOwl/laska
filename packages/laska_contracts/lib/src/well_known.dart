/// The well-known types of the protocol buffers and their Dart counterparts.
///
/// The types are the ones a contract may use without declaring them. They are
/// not part of the model of a contract — they are the same for every contract
/// — and they are compiled into the types of the runtime, so every service of
/// a contract speaks of them with the same Dart types.
library;

/// The shape of the JSON of a well-known type.
enum WellKnownJson {
  /// The time in the format of RFC 3339.
  timestamp,

  /// The number of seconds and the letter `s`.
  duration,

  /// The address of the type and the bytes of the message.
  any,

  /// An empty object.
  empty,
}

/// A well-known type of the protocol buffers.
class WellKnownType {
  /// Creates a description of a well-known type.
  const WellKnownType({
    required this.protoName,
    required this.dartName,
    required this.jsonKind,
    required this.protoPath,
  });

  /// The name of the type in a contract, e.g. `google.protobuf.Timestamp`.
  final String protoName;

  /// The name of the Dart type the contract is compiled into.
  final String dartName;

  /// The shape of the JSON of the type.
  final WellKnownJson jsonKind;

  /// The path of the file the type is declared in, e.g.
  /// `google/protobuf/timestamp.proto`.
  final String protoPath;

  /// Whether the JSON of the type is a string and not an object.
  bool get isTextJson =>
      jsonKind == WellKnownJson.timestamp || jsonKind == WellKnownJson.duration;
}

/// The well-known types, by the name they are written with in a contract.
const Map<String, WellKnownType> wellKnownTypes = <String, WellKnownType>{
  'google.protobuf.Timestamp': WellKnownType(
    protoName: 'google.protobuf.Timestamp',
    dartName: 'ProtoTimestamp',
    jsonKind: WellKnownJson.timestamp,
    protoPath: 'google/protobuf/timestamp.proto',
  ),
  'google.protobuf.Duration': WellKnownType(
    protoName: 'google.protobuf.Duration',
    dartName: 'ProtoDuration',
    jsonKind: WellKnownJson.duration,
    protoPath: 'google/protobuf/duration.proto',
  ),
  'google.protobuf.Any': WellKnownType(
    protoName: 'google.protobuf.Any',
    dartName: 'ProtoAny',
    jsonKind: WellKnownJson.any,
    protoPath: 'google/protobuf/any.proto',
  ),
  'google.protobuf.Empty': WellKnownType(
    protoName: 'google.protobuf.Empty',
    dartName: 'ProtoEmpty',
    jsonKind: WellKnownJson.empty,
    protoPath: 'google/protobuf/empty.proto',
  ),
};

/// The well-known types, by the path of the file they are declared in.
final Map<String, WellKnownType> wellKnownFiles = <String, WellKnownType>{
  for (final type in wellKnownTypes.values) type.protoPath: type,
};

/// The well-known type the name [reference] points to, if it points to one.
WellKnownType? wellKnownTypeOf(String reference) => wellKnownTypes[reference];

/// The well-known type the file [path] declares, if it declares one.
WellKnownType? wellKnownFileOf(String path) => wellKnownFiles[path];
