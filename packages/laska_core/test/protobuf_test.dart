import 'dart:convert';
import 'dart:typed_data';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProtoWriter', () {
    test('writes the fields of a message', () {
      final writer = ProtoWriter()
        ..writeString(1, 'hello')
        ..writeInt32(2, 42)
        ..writeBool(3, true)
        ..writeDouble(4, 1.5)
        ..writeEnum(5, 2)
        ..writeMessage(6, <int>[1, 2, 3]);

      final bytes = writer.toBytes();

      expect(bytes, isNotEmpty);
      // The first field is the tag of the first field: field 1, length
      // delimited.
      expect(bytes.first, 0x0a);
    });

    test('writes the values it is told to write', () {
      final writer = ProtoWriter()
        ..writeString(1, '')
        ..writeInt32(2, 0)
        ..writeBool(3, false);

      expect(writer.toBytes(), isNotEmpty);
    });

    test('writes the value of a boolean, not only its tag', () {
      final writer = ProtoWriter()..writeBool(1, false);
      final bytes = writer.toBytes();

      // The tag of the field, and then the value: 0 is false.
      expect(bytes, <int>[0x08, 0x00]);

      final reader = ProtoReader(bytes);
      reader.readTag();
      expect(reader.readBool(), isFalse);
    });
  });

  group('ProtoReader', () {
    test('reads the fields that were written', () {
      final writer = ProtoWriter()
        ..writeString(1, 'hello')
        ..writeInt32(2, 42)
        ..writeBool(3, true)
        ..writeDouble(4, 1.5)
        ..writeEnum(5, 2)
        ..writeBytes(6, <int>[7, 8, 9]);

      final reader = ProtoReader(writer.toBytes());
      final fields = <int, Object?>{};

      while (reader.hasNext) {
        final tag = reader.readTag();
        switch (tag) {
          case 1:
            fields[tag] = reader.readString();
          case 2:
            fields[tag] = reader.readInt32();
          case 3:
            fields[tag] = reader.readBool();
          case 4:
            fields[tag] = reader.readDouble();
          case 5:
            fields[tag] = reader.readEnum();
          case 6:
            fields[tag] = reader.readBytes();
        }
      }

      expect(fields[1], 'hello');
      expect(fields[2], 42);
      expect(fields[3], isTrue);
      expect(fields[4], 1.5);
      expect(fields[5], 2);
      expect(fields[6], <int>[7, 8, 9]);
    });

    test('skips the fields it does not know', () {
      final writer = ProtoWriter()
        ..writeString(1, 'hello')
        ..writeInt64(9, 1234567890123)
        ..writeString(2, 'world');

      final reader = ProtoReader(writer.toBytes());
      final fields = <int, String>{};

      while (reader.hasNext) {
        final tag = reader.readTag();
        if (tag == 1 || tag == 2) {
          fields[tag] = reader.readString();
        } else {
          reader.skipField();
        }
      }

      expect(fields[1], 'hello');
      expect(fields[2], 'world');
    });

    test('skips a field of bytes it does not know', () {
      final writer = ProtoWriter()
        ..writeString(1, 'hello')
        ..writeBytes(9, <int>[1, 2, 3, 4, 5])
        ..writeString(2, 'world');

      final reader = ProtoReader(writer.toBytes());
      final fields = <int, String>{};

      while (reader.hasNext) {
        final tag = reader.readTag();
        if (tag == 1 || tag == 2) {
          fields[tag] = reader.readString();
        } else {
          reader.skipField();
        }
      }

      expect(fields[1], 'hello');
      expect(fields[2], 'world');
    });

    test('reads a repeated field that is packed', () {
      final packed = ProtoWriter()..writeString(1, 'a');
      final payload = <int>[];
      for (final byte in packed.toBytes()) {
        payload.add(byte);
      }

      // The values are packed in one length delimited field.
      final writer = ProtoWriter()..writeMessage(1, payload);
      final reader = ProtoReader(writer.toBytes());

      reader.readTag();
      final nested = ProtoReader(reader.readBytes());
      final values = <int>[];
      while (nested.hasNext) {
        nested.readTag();
        values.add(nested.readVarint());
      }

      expect(values, isNotEmpty);
    });

    test('reads a negative number that was written as a varint', () {
      final writer = ProtoWriter()..writeInt32(1, -5);
      final reader = ProtoReader(writer.toBytes());

      reader.readTag();

      expect(reader.readInt32(), -5);
    });

    test('reads a string that holds characters outside of the ASCII', () {
      final writer = ProtoWriter()..writeString(1, 'привет');
      final reader = ProtoReader(writer.toBytes());

      reader.readTag();

      expect(reader.readString(), 'привет');
    });
  });

  group('the wire format', () {
    test('writes a tag of a field as the field number and the type', () {
      final writer = ProtoWriter()..writeString(3, 'x');
      final bytes = writer.toBytes();

      // Field 3, wire type 2 → (3 << 3) | 2 = 0x1a.
      expect(bytes.first, 0x1a);
      expect(bytes[1], 1);
      expect(utf8.decode(bytes.sublist(2)), 'x');
    });

    test('writes a double in the little endian order', () {
      final writer = ProtoWriter()..writeDouble(1, 1.0);
      final bytes = writer.toBytes();

      expect(bytes[1], 0);
      expect(
        ByteData.view(Uint8List.fromList(bytes.sublist(1)).buffer)
            .getFloat64(0, Endian.little),
        1.0,
      );
    });
  });
}
