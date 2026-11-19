import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('ProtoTimestamp', () {
    test('reads the date and the time of a date', () {
      final timestamp = ProtoTimestamp.fromDateTime(
        DateTime.utc(2026, 11, 19, 10, 30, 15, 250),
      );

      expect(timestamp.seconds, 1795084215);
      expect(timestamp.nanos, 250000000);
      expect(
          timestamp.toDateTime(), DateTime.utc(2026, 11, 19, 10, 30, 15, 250));
    });

    test('writes the time in the format of RFC 3339', () {
      expect(
        ProtoTimestamp(seconds: 1795084215).toJson(),
        '2026-11-19T10:30:15Z',
      );
      expect(
        ProtoTimestamp(seconds: 1795084215, nanos: 250000000).toJson(),
        '2026-11-19T10:30:15.250Z',
      );
      expect(
        ProtoTimestamp(seconds: 1795084215, nanos: 250000001).toJson(),
        '2026-11-19T10:30:15.250000001Z',
      );
    });

    test('reads the time out of the format of RFC 3339', () {
      final timestamp = ProtoTimestamp.fromJson('2026-11-19T10:30:15.250Z');

      expect(timestamp.seconds, 1795084215);
      expect(timestamp.nanos, 250000000);
    });

    test('refuses a time that is not a time', () {
      expect(
        () => ProtoTimestamp.fromJson(42),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ProtoTimestamp.fromJson('yesterday'),
        throwsA(isA<FormatException>()),
      );
    });

    test('writes the timestamp on the wire', () {
      final timestamp = ProtoTimestamp(seconds: 1795084215, nanos: 250000000);

      final bytes = timestamp.toProtoBytes();

      expect(ProtoTimestamp.fromProtoBytes(bytes), timestamp);
    });

    test('reads a timestamp of another implementation', () {
      // The bytes of the message {seconds: 1, nanos: 2} of the wire format.
      final bytes = <int>[0x08, 0x01, 0x10, 0x02];

      final timestamp = ProtoTimestamp.fromProtoBytes(bytes);

      expect(timestamp.seconds, 1);
      expect(timestamp.nanos, 2);
    });

    test('is equal to a timestamp of the same time', () {
      expect(
        ProtoTimestamp(seconds: 1, nanos: 2),
        ProtoTimestamp(seconds: 1, nanos: 2),
      );
      expect(
        ProtoTimestamp(seconds: 1, nanos: 2),
        isNot(ProtoTimestamp(seconds: 1, nanos: 3)),
      );
    });
  });

  group('ProtoDuration', () {
    test('reads the duration of a duration', () {
      final duration = ProtoDuration.fromDuration(
        const Duration(seconds: 3, milliseconds: 500),
      );

      expect(duration.seconds, 3);
      expect(duration.nanos, 500000000);
      expect(
        duration.toDuration(),
        const Duration(seconds: 3, milliseconds: 500),
      );
    });

    test('writes the number of seconds', () {
      expect(ProtoDuration(seconds: 3).toJson(), '3s');
      expect(ProtoDuration(seconds: 3, nanos: 500000000).toJson(), '3.500s');
      expect(ProtoDuration(seconds: 3, nanos: 1).toJson(), '3.000000001s');
      expect(ProtoDuration(seconds: -3, nanos: 500000000).toJson(), '-3.500s');
    });

    test('reads the number of seconds', () {
      final duration = ProtoDuration.fromJson('3.500s');

      expect(duration.seconds, 3);
      expect(duration.nanos, 500000000);
    });

    test('refuses a duration that is not a duration', () {
      expect(
        () => ProtoDuration.fromJson(42),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ProtoDuration.fromJson('3'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ProtoDuration.fromJson('3.5 seconds'),
        throwsA(isA<FormatException>()),
      );
    });

    test('writes the duration on the wire', () {
      final duration = ProtoDuration(seconds: 3, nanos: 500000000);

      final bytes = duration.toProtoBytes();

      expect(ProtoDuration.fromProtoBytes(bytes), duration);
    });
  });

  group('ProtoAny', () {
    test('writes the address of the type and the bytes of the message', () {
      final any = ProtoAny(
        typeUrl: 'type.googleapis.com/shop.v1.Order',
        value: <int>[1, 2, 3],
      );

      final json = any.toJson();

      expect(json['@type'], 'type.googleapis.com/shop.v1.Order');
      expect(json['value'], 'AQID');
    });

    test('reads the address of the type and the bytes of the message', () {
      final any = ProtoAny.fromJson(<String, dynamic>{
        '@type': 'type.googleapis.com/shop.v1.Order',
        'value': 'AQID',
      });

      expect(any.typeUrl, 'type.googleapis.com/shop.v1.Order');
      expect(any.value, <int>[1, 2, 3]);
    });

    test('refuses a value without the address of its type', () {
      expect(
        () => ProtoAny.fromJson(<String, dynamic>{'value': 'AQID'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ProtoAny.fromJson('AQID'),
        throwsA(isA<FormatException>()),
      );
    });

    test('writes the value on the wire', () {
      final any = ProtoAny(
        typeUrl: 'type.googleapis.com/shop.v1.Order',
        value: <int>[1, 2, 3],
      );

      final bytes = any.toProtoBytes();

      expect(ProtoAny.fromProtoBytes(bytes), any);
    });
  });

  group('ProtoEmpty', () {
    test('writes an empty object', () {
      expect(const ProtoEmpty().toJson(), <String, dynamic>{});
    });

    test('holds no byte on the wire', () {
      expect(const ProtoEmpty().toProtoBytes(), isEmpty);
      expect(ProtoEmpty.fromProtoBytes(<int>[]), const ProtoEmpty());
    });
  });
}
