/// The wire format of the protocol buffers.
///
/// The codec is the small part of the format Laska needs: the varint, the
/// fixed 32 and 64 bit numbers, the strings, the bytes and the embedded
/// messages. The generated code of a contract uses it, so a service can speak
/// the binary format of its contract without a toolchain.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The wire types of the protocol buffers.
class WireType {
  const WireType._();

  /// A variable length integer.
  static const int varint = 0;

  /// A fixed 64 bit number.
  static const int fixed64 = 1;

  /// A length delimited value.
  static const int lengthDelimited = 2;

  /// A fixed 32 bit number.
  static const int fixed32 = 5;
}

/// Writes the wire format of the protocol buffers.
///
/// The writer writes what it is told to write: the values of the default of a
/// field are left out by the caller, so a repeated field keeps every one of
/// its values.
class ProtoWriter {
  final BytesBuilder _bytes = BytesBuilder();

  /// The bytes that were written.
  List<int> toBytes() => _bytes.toBytes();

  /// Writes a signed 32 bit integer.
  void writeInt32(int field, int value) {
    _writeTag(field, WireType.varint);
    _writeVarint(value);
  }

  /// Writes a signed 64 bit integer.
  void writeInt64(int field, int value) {
    _writeTag(field, WireType.varint);
    _writeVarint(value);
  }

  /// Writes an unsigned 32 bit integer.
  void writeUInt32(int field, int value) {
    _writeTag(field, WireType.varint);
    _writeVarint(value);
  }

  /// Writes an unsigned 64 bit integer.
  void writeUInt64(int field, int value) {
    _writeTag(field, WireType.varint);
    _writeVarint(value);
  }

  /// Writes a signed 32 bit integer in the zigzag form.
  void writeSInt32(int field, int value) {
    _writeTag(field, WireType.varint);
    _writeVarint(_zigzag32(value));
  }

  /// Writes a signed 64 bit integer in the zigzag form.
  void writeSInt64(int field, int value) {
    _writeTag(field, WireType.varint);
    _writeVarint(_zigzag64(value));
  }

  /// Writes a boolean.
  void writeBool(int field, bool value) {
    _writeTag(field, WireType.varint);
    _writeVarint(1);
  }

  /// Writes the number of an enum value.
  void writeEnum(int field, int value) {
    _writeTag(field, WireType.varint);
    _writeVarint(value);
  }

  /// Writes a fixed 64 bit number.
  void writeFixed64(int field, int value) {
    _writeTag(field, WireType.fixed64);
    _writeFixed64(value);
  }

  /// Writes a signed fixed 64 bit number.
  void writeSFixed64(int field, int value) {
    _writeTag(field, WireType.fixed64);
    _writeFixed64(value);
  }

  /// Writes a double.
  void writeDouble(int field, double value) {
    _writeTag(field, WireType.fixed64);
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  /// Writes a fixed 32 bit number.
  void writeFixed32(int field, int value) {
    _writeTag(field, WireType.fixed32);
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  /// Writes a signed fixed 32 bit number.
  void writeSFixed32(int field, int value) {
    _writeTag(field, WireType.fixed32);
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  /// Writes a float.
  void writeFloat(int field, double value) {
    _writeTag(field, WireType.fixed32);
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  /// Writes a string.
  void writeString(int field, String value) {
    _writeTag(field, WireType.lengthDelimited);
    _writeLengthDelimited(utf8.encode(value));
  }

  /// Writes bytes.
  void writeBytes(int field, List<int> value) {
    _writeTag(field, WireType.lengthDelimited);
    _writeLengthDelimited(value);
  }

  /// Writes an embedded message.
  void writeMessage(int field, List<int> value) {
    _writeTag(field, WireType.lengthDelimited);
    _writeLengthDelimited(value);
  }

  void _writeTag(int field, int wireType) {
    _writeVarint((field << 3) | wireType);
  }

  void _writeVarint(int value) {
    var remaining = value;
    while (remaining < 0 || remaining > 0x7f) {
      _bytes.addByte((remaining & 0x7f) | 0x80);
      remaining = remaining >>> 7;
    }
    _bytes.addByte(remaining & 0x7f);
  }

  void _writeFixed64(int value) {
    final data = ByteData(8)..setInt64(0, value, Endian.little);
    _bytes.add(data.buffer.asUint8List());
  }

  void _writeLengthDelimited(List<int> value) {
    _writeVarint(value.length);
    _bytes.add(value);
  }

  static int _zigzag32(int value) =>
      ((value << 1) ^ (value >> 31)).toUnsigned(32);

  static int _zigzag64(int value) => (value << 1) ^ (value >> 63);
}

/// Reads the wire format of the protocol buffers.
///
/// The reader walks the fields of a message one by one. A field the caller
/// does not know is skipped, so a message of a newer version of a contract can
/// still be read.
class ProtoReader {
  /// Creates a reader over [bytes].
  ProtoReader(List<int> bytes) : _bytes = bytes;

  final List<int> _bytes;
  int _pos = 0;
  int _wireType = WireType.varint;

  /// Whether there is another field to read.
  bool get hasNext => _pos < _bytes.length;

  /// The wire type of the field that was read last.
  int get wireType => _wireType;

  /// Reads the number of the next field.
  int readTag() {
    final tag = _readVarint();
    _wireType = tag & 0x7;
    return tag >> 3;
  }

  /// Reads a variable length integer.
  int readVarint() => _readVarint();

  /// Reads a signed 32 bit integer.
  int readInt32() => _readVarint();

  /// Reads a signed 64 bit integer.
  int readInt64() => _readVarint();

  /// Reads a boolean.
  bool readBool() => _readVarint() != 0;

  /// Reads the number of an enum value.
  int readEnum() => _readVarint();

  /// Reads a signed 32 bit integer in the zigzag form.
  int readSInt32() => _unzigzag32(_readVarint());

  /// Reads a signed 64 bit integer in the zigzag form.
  int readSInt64() => _unzigzag64(_readVarint());

  /// Reads a fixed 64 bit number.
  int readFixed64() {
    final value = ByteData.view(
      Uint8List.fromList(_bytes.sublist(_pos, _pos + 8)).buffer,
    ).getInt64(0, Endian.little);
    _pos += 8;
    return value;
  }

  /// Reads a signed fixed 64 bit number.
  int readSFixed64() {
    final value = ByteData.view(
      Uint8List.fromList(_bytes.sublist(_pos, _pos + 8)).buffer,
    ).getInt64(0, Endian.little);
    _pos += 8;
    return value;
  }

  /// Reads a double.
  double readDouble() {
    final value = ByteData.view(
      Uint8List.fromList(_bytes.sublist(_pos, _pos + 8)).buffer,
    ).getFloat64(0, Endian.little);
    _pos += 8;
    return value;
  }

  /// Reads a fixed 32 bit number.
  int readFixed32() {
    final value = ByteData.view(
      Uint8List.fromList(_bytes.sublist(_pos, _pos + 4)).buffer,
    ).getUint32(0, Endian.little);
    _pos += 4;
    return value;
  }

  /// Reads a signed fixed 32 bit number.
  int readSFixed32() {
    final value = ByteData.view(
      Uint8List.fromList(_bytes.sublist(_pos, _pos + 4)).buffer,
    ).getInt32(0, Endian.little);
    _pos += 4;
    return value;
  }

  /// Reads a float.
  double readFloat() {
    final value = ByteData.view(
      Uint8List.fromList(_bytes.sublist(_pos, _pos + 4)).buffer,
    ).getFloat32(0, Endian.little);
    _pos += 4;
    return value;
  }

  /// Reads a string.
  String readString() {
    final bytes = readBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Reads bytes.
  List<int> readBytes() {
    final length = _readVarint();
    final bytes = _bytes.sublist(_pos, _pos + length);
    _pos += length;
    return bytes;
  }

  /// Reads the values of a repeated field of numbers.
  ///
  /// The values are read one by one or packed in one field, the format allows
  /// both.
  List<int> readRepeatedVarint(List<int> values) {
    if (_wireType == WireType.lengthDelimited) {
      final reader = ProtoReader(readBytes());
      while (reader.hasNext) {
        values.add(reader.readVarint());
      }
      return values;
    }
    values.add(_readVarint());
    return values;
  }

  /// Reads the values of a repeated field of fixed 64 bit numbers.
  List<int> readRepeatedFixed64(List<int> values) {
    if (_wireType == WireType.lengthDelimited) {
      final reader = ProtoReader(readBytes());
      while (reader.hasNext) {
        values.add(reader.readFixed64());
      }
      return values;
    }
    values.add(readFixed64());
    return values;
  }

  /// Reads the values of a repeated field of fixed 32 bit numbers.
  List<int> readRepeatedFixed32(List<int> values) {
    if (_wireType == WireType.lengthDelimited) {
      final reader = ProtoReader(readBytes());
      while (reader.hasNext) {
        values.add(reader.readFixed32());
      }
      return values;
    }
    values.add(readFixed32());
    return values;
  }

  /// Reads the values of a repeated field of signed 32 bit integers.
  List<int> readRepeatedSInt32(List<int> values) {
    if (_wireType == WireType.lengthDelimited) {
      final reader = ProtoReader(readBytes());
      while (reader.hasNext) {
        values.add(reader.readSInt32());
      }
      return values;
    }
    values.add(readSInt32());
    return values;
  }

  /// Reads the values of a repeated field of signed 64 bit integers.
  List<int> readRepeatedSInt64(List<int> values) {
    if (_wireType == WireType.lengthDelimited) {
      final reader = ProtoReader(readBytes());
      while (reader.hasNext) {
        values.add(reader.readSInt64());
      }
      return values;
    }
    values.add(readSInt64());
    return values;
  }

  /// Reads the values of a repeated field of doubles.
  List<double> readRepeatedDouble(List<double> values) {
    if (_wireType == WireType.lengthDelimited) {
      final reader = ProtoReader(readBytes());
      while (reader.hasNext) {
        values.add(reader.readDouble());
      }
      return values;
    }
    values.add(readDouble());
    return values;
  }

  /// Reads the values of a repeated field of floats.
  List<double> readRepeatedFloat(List<double> values) {
    if (_wireType == WireType.lengthDelimited) {
      final reader = ProtoReader(readBytes());
      while (reader.hasNext) {
        values.add(reader.readFloat());
      }
      return values;
    }
    values.add(readFloat());
    return values;
  }

  /// Skips the field that was read last.
  void skipField() {
    switch (_wireType) {
      case WireType.varint:
        _readVarint();
      case WireType.fixed64:
        _pos += 8;
      case WireType.lengthDelimited:
        _pos += _readVarint();
      case WireType.fixed32:
        _pos += 4;
      default:
        _pos = _bytes.length;
    }
  }

  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (_pos < _bytes.length) {
      final byte = _bytes[_pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift > 63) {
        return result;
      }
    }
    return result;
  }

  static int _unzigzag32(int value) =>
      ((value >> 1) ^ -(value & 1)).toUnsigned(32);

  static int _unzigzag64(int value) => (value >> 1) ^ -(value & 1);
}
