import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _source = '''
syntax = "proto3";

package shop.v1;

import "google/protobuf/any.proto";
import "google/protobuf/duration.proto";
import "google/protobuf/timestamp.proto";

// An order of a shop.
message Order {
  // Stable identifier of the order.
  string id = 1;

  // The moment the order was placed.
  google.protobuf.Timestamp placed_at = 2;

  // How long the delivery takes.
  google.protobuf.Duration delivery_time = 3;

  // The payload of the order.
  google.protobuf.Any payload = 4;

  // The moments the order was changed at.
  repeated google.protobuf.Timestamp changed_at = 5;

  // The moment the order was cancelled at.
  optional google.protobuf.Timestamp cancelled_at = 6;
}
''';

CompileResult _compile([String source = _source]) =>
    ContractCompiler().compile(<ProtoSource>[
      ProtoSource('shop.proto', source),
    ]);

void main() {
  group('the well-known types', () {
    test('are types a contract may use', () {
      final result = _compile();

      expect(result.warnings.where((w) => w.contains('unknown')), isEmpty);
    });

    test('are compiled into the types of the runtime', () {
      final result = _compile();

      final order = result.contract.messages.first;
      final placedAt = order.field('placed_at')!;
      final resolver = TypeResolver(result.contract);
      final type = resolver.resolve(placedAt);

      expect(type.dartType, 'ProtoTimestamp');
      expect(type.isMessage, isTrue);
      expect(type.isWellKnown, isTrue);
    });

    test('are read out of the JSON as the way protobuf writes them', () {
      final result = _compile();

      final code = result.files.first.content;

      expect(code, contains('ProtoTimestamp.fromJson'));
      expect(code, contains('ProtoDuration.fromJson'));
      expect(code, contains('ProtoAny.fromJson'));
      expect(code, contains('must be a string'));
    });

    test('are written on the wire as the way protobuf writes them', () {
      final result = _compile();

      final code = result.files.first.content;

      expect(code, contains('ProtoTimestamp.fromProtoBytes'));
      expect(code, contains('ProtoAny.fromProtoBytes'));
    });

    test('are described in the OpenAPI document', () {
      final result = _compile();

      final schemas =
          result.openapi['components']['schemas'] as Map<String, dynamic>;
      final order = schemas['Order'] as Map<String, dynamic>;
      final properties = order['properties'] as Map<String, dynamic>;

      expect(properties['placedAt'], <String, dynamic>{
        'type': 'string',
        'format': 'date-time',
      });
      expect(properties['deliveryTime'], <String, dynamic>{'type': 'string'});
      expect(properties['payload'], <String, dynamic>{'type': 'object'});
      expect(properties['changedAt'], <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string', 'format': 'date-time'},
      });
    });

    test('may not take the name of a type of the runtime', () {
      expect(
        () => _compile('''
syntax = "proto3";

package shop.v1;

message ProtoTimestamp {
  string id = 1;
}
'''),
        throwsA(isA<ContractCompileException>()),
      );
    });

    test('may be the request and the answer of a method', () {
      final result = _compile('''
syntax = "proto3";

package shop.v1;

import "google/protobuf/empty.proto";

service ShopService {
  rpc Ping(google.protobuf.Empty) returns (google.protobuf.Empty);
}
''');

      expect(result.contract.services, hasLength(1));
    });
  });
}
