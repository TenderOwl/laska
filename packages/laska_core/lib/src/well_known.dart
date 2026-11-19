/// The well-known types of the protocol buffers.
///
/// The types are the ones every contract may use without declaring them: a
/// point in time, a span of time, a value of any type and an empty message.
/// They live in the runtime and not in the generated code, so every service of
/// a contract speaks of them with the same Dart types, and the wire format and
/// the JSON of the protocol buffers are written once.
///
/// The names carry the `Proto` prefix, because the name of the type in the
/// contract is the name of the file it comes from: `google.protobuf.Timestamp`
/// is a `ProtoTimestamp` in Dart, and a contract is free to declare a message
/// of its own called `Timestamp`.
library;

import 'dart:convert';

import 'protobuf.dart';

/// A point in time — the `google.protobuf.Timestamp` of the protocol buffers.
///
/// The timestamp is a number of seconds since the epoch and a number of
/// nanoseconds within the second, the way protobuf writes it on the wire. In
/// JSON it is the time in the format of RFC 3339, the way every other
/// implementation of protobuf writes it.
class ProtoTimestamp {
  /// Creates a timestamp.
  const ProtoTimestamp({required this.seconds, this.nanos = 0});

  /// Creates a timestamp out of a date and a time.
  factory ProtoTimestamp.fromDateTime(DateTime value) {
    final micros = value.toUtc().microsecondsSinceEpoch;
    return ProtoTimestamp(
      seconds: micros ~/ 1000000,
      nanos: (micros % 1000000) * 1000,
    );
  }

  /// Reads a timestamp out of its JSON representation.
  ///
  /// The JSON of a timestamp is the time in the format of RFC 3339.
  factory ProtoTimestamp.fromJson(Object? json) {
    if (json is! String) {
      throw FormatException(
        'A timestamp is a string in the format of RFC 3339, got '
        '${json.runtimeType}',
      );
    }

    final DateTime value;
    try {
      value = DateTime.parse(json);
    } on FormatException {
      throw FormatException('"$json" is not a time in the format of RFC 3339');
    }

    return ProtoTimestamp.fromDateTime(value);
  }

  /// Reads a timestamp out of the bytes of the wire format.
  factory ProtoTimestamp.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var seconds = 0;
    var nanos = 0;

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          seconds = reader.readInt64();
        case 2:
          nanos = reader.readInt32();
        default:
          reader.skipField();
      }
    }

    return ProtoTimestamp(seconds: seconds, nanos: nanos);
  }

  /// The seconds since the epoch.
  final int seconds;

  /// The nanoseconds within the second.
  final int nanos;

  /// The date and the time of the timestamp.
  ///
  /// The date and the time of Dart hold microseconds, so the nanoseconds that
  /// are not a whole microsecond are lost on the way.
  DateTime toDateTime() => DateTime.fromMicrosecondsSinceEpoch(
        seconds * 1000000 + nanos ~/ 1000,
        isUtc: true,
      );

  /// The JSON representation of the timestamp.
  ///
  /// The time is written in the format of RFC 3339, with the fraction of the
  /// second in three, six or nine digits, the way protobuf writes it.
  String toJson() {
    final date = DateTime.fromMicrosecondsSinceEpoch(
      seconds * 1000000,
      isUtc: true,
    );
    // The date of Dart writes the fraction of the second always, so it is
    // taken off before the nanoseconds are written.
    final stem = date.toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), '');

    if (nanos == 0) {
      return '${stem}Z';
    }

    var digits = nanos.toString().padLeft(9, '0');
    while (digits.length > 3 && digits.endsWith('000')) {
      digits = digits.substring(0, digits.length - 3);
    }
    return '$stem.${digits}Z';
  }

  /// The bytes of the timestamp in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    writer.writeInt64(1, seconds);
    if (nanos != 0) {
      writer.writeInt32(2, nanos);
    }
    return writer.toBytes();
  }

  @override
  String toString() => toJson();

  @override
  bool operator ==(Object other) =>
      other is ProtoTimestamp &&
      other.seconds == seconds &&
      other.nanos == nanos;

  @override
  int get hashCode => Object.hash(seconds, nanos);
}

/// A span of time — the `google.protobuf.Duration` of the protocol buffers.
///
/// The span is a number of seconds and a number of nanoseconds within the
/// second, the way protobuf writes it on the wire. In JSON it is the number
/// of seconds and the letter `s`, the way every other implementation of
/// protobuf writes it.
class ProtoDuration {
  /// Creates a span of time.
  const ProtoDuration({required this.seconds, this.nanos = 0});

  /// Creates a span of time out of a duration.
  factory ProtoDuration.fromDuration(Duration value) {
    final micros = value.inMicroseconds;
    return ProtoDuration(
      seconds: micros ~/ 1000000,
      nanos: (micros % 1000000) * 1000,
    );
  }

  /// Reads a span of time out of its JSON representation.
  ///
  /// The JSON of a duration is a number of seconds and the letter `s`.
  factory ProtoDuration.fromJson(Object? json) {
    if (json is! String) {
      throw FormatException(
        'A duration is a string of seconds, got ${json.runtimeType}',
      );
    }
    if (!json.endsWith('s')) {
      throw FormatException('"$json" is not a duration of seconds');
    }

    final text = json.substring(0, json.length - 1);
    final parts = text.split('.');
    if (parts.length > 2) {
      throw FormatException('"$json" is not a duration of seconds');
    }

    final seconds = int.tryParse(parts.first);
    if (seconds == null) {
      throw FormatException('"$json" is not a duration of seconds');
    }

    var nanos = 0;
    if (parts.length == 2) {
      final fraction = parts[1];
      if (fraction.isEmpty ||
          fraction.length > 9 ||
          !RegExp(r'^\d+$').hasMatch(fraction)) {
        throw FormatException('"$json" is not a duration of seconds');
      }
      nanos = int.parse(fraction.padRight(9, '0'));
    }

    return ProtoDuration(seconds: seconds, nanos: nanos);
  }

  /// Reads a span of time out of the bytes of the wire format.
  factory ProtoDuration.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var seconds = 0;
    var nanos = 0;

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          seconds = reader.readInt64();
        case 2:
          nanos = reader.readInt32();
        default:
          reader.skipField();
      }
    }

    return ProtoDuration(seconds: seconds, nanos: nanos);
  }

  /// The seconds of the span.
  final int seconds;

  /// The nanoseconds within the second.
  final int nanos;

  /// The span of time as a duration.
  ///
  /// The duration of Dart holds microseconds, so the nanoseconds that are not a
  /// whole microsecond are lost on the way.
  Duration toDuration() => Duration(
        microseconds: seconds * 1000000 + nanos ~/ 1000,
      );

  /// The JSON representation of the span of time.
  String toJson() {
    final sign = seconds < 0 || (seconds == 0 && nanos < 0) ? '-' : '';
    final whole = seconds.abs();
    final fraction = nanos.abs();

    if (fraction == 0) {
      return '$sign${whole}s';
    }

    var digits = fraction.toString().padLeft(9, '0');
    while (digits.length > 3 && digits.endsWith('000')) {
      digits = digits.substring(0, digits.length - 3);
    }
    return '$sign$whole.${digits}s';
  }

  /// The bytes of the span of time in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    writer.writeInt64(1, seconds);
    if (nanos != 0) {
      writer.writeInt32(2, nanos);
    }
    return writer.toBytes();
  }

  @override
  String toString() => toJson();

  @override
  bool operator ==(Object other) =>
      other is ProtoDuration &&
      other.seconds == seconds &&
      other.nanos == nanos;

  @override
  int get hashCode => Object.hash(seconds, nanos);
}

/// A value of any type — the `google.protobuf.Any` of the protocol buffers.
///
/// The value carries the address of the type it holds and the bytes of the
/// message of that type. In JSON the address is written under the name
/// `@type`, the way protobuf writes it, and the bytes of the message are
/// written as text in base64: the JSON of a value of any type needs the
/// registry of the messages to hold the message itself, and the runtime does
/// not hold it.
class ProtoAny {
  /// Creates a value of any type.
  const ProtoAny({required this.typeUrl, this.value = const <int>[]});

  /// Reads a value of any type out of its JSON representation.
  factory ProtoAny.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw FormatException(
        'A value of any type is an object, got ${json.runtimeType}',
      );
    }

    final typeUrl = json['@type'];
    if (typeUrl is! String || typeUrl.isEmpty) {
      throw const FormatException(
        'A value of any type carries the address of its type under "@type"',
      );
    }

    final value = json['value'];
    if (value == null) {
      return ProtoAny(typeUrl: typeUrl);
    }
    if (value is! String) {
      throw const FormatException(
        'The value of a value of any type is a string in base64',
      );
    }

    try {
      return ProtoAny(typeUrl: typeUrl, value: base64Decode(value));
    } on FormatException {
      throw const FormatException(
        'The value of a value of any type is a string in base64',
      );
    }
  }

  /// Reads a value of any type out of the bytes of the wire format.
  factory ProtoAny.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var typeUrl = '';
    var value = const <int>[];

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          typeUrl = reader.readString();
        case 2:
          value = reader.readBytes();
        default:
          reader.skipField();
      }
    }

    return ProtoAny(typeUrl: typeUrl, value: value);
  }

  /// The address of the type of the value, e.g.
  /// `type.googleapis.com/users.v1.User`.
  final String typeUrl;

  /// The bytes of the message the value holds.
  final List<int> value;

  /// The JSON representation of the value.
  Map<String, dynamic> toJson() => <String, dynamic>{
        '@type': typeUrl,
        'value': base64Encode(value),
      };

  /// The bytes of the value in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (typeUrl.isNotEmpty) {
      writer.writeString(1, typeUrl);
    }
    if (value.isNotEmpty) {
      writer.writeBytes(2, value);
    }
    return writer.toBytes();
  }

  @override
  String toString() => 'ProtoAny($typeUrl)';

  @override
  bool operator ==(Object other) =>
      other is ProtoAny &&
      other.typeUrl == typeUrl &&
      _sameBytes(other.value, value);

  @override
  int get hashCode => Object.hash(typeUrl, Object.hashAll(value));
}

/// An empty message — the `google.protobuf.Empty` of the protocol buffers.
///
/// The message holds no field, so it says the same thing as nothing at all,
/// and it is the answer of a call that has nothing to answer.
class ProtoEmpty {
  /// Creates an empty message.
  const ProtoEmpty();

  /// Reads an empty message out of its JSON representation.
  factory ProtoEmpty.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw FormatException(
        'An empty message is an object, got ${json.runtimeType}',
      );
    }
    return const ProtoEmpty();
  }

  /// Reads an empty message out of the bytes of the wire format.
  factory ProtoEmpty.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    while (reader.hasNext) {
      reader.readTag();
      reader.skipField();
    }
    return const ProtoEmpty();
  }

  /// The JSON representation of the empty message.
  Map<String, dynamic> toJson() => <String, dynamic>{};

  /// The bytes of the empty message in the wire format of the protocol
  /// buffers.
  List<int> toProtoBytes() => <int>[];

  @override
  String toString() => 'ProtoEmpty()';

  @override
  bool operator ==(Object other) => other is ProtoEmpty;

  @override
  int get hashCode => 0;
}

/// Whether the two lists of bytes hold the same bytes.
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
