import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _common = '''
syntax = "proto3";

package common.v1;

// The money of an amount.
message Money {
  // The currency of the amount.
  string currency = 1;

  // The amount, in the smallest unit of the currency.
  int64 amount = 2;
}
''';

const String _orders = '''
syntax = "proto3";

package orders.v1;

import "common.proto";

// An order of a shop.
message Order {
  // The identifier of the order.
  string id = 1;

  // What the order costs.
  common.v1.Money total = 2;
}
''';

CompileResult _compile(List<ProtoSource> sources) =>
    ContractCompiler().compile(sources);

void main() {
  group('the imports of a contract', () {
    test('make the types of the imported file visible', () {
      final result = _compile(<ProtoSource>[
        ProtoSource('common.proto', _common),
        ProtoSource('orders.proto', _orders),
      ]);

      expect(result.contract.messages, hasLength(2));
      expect(
        result.contract.message('orders.v1.Order')!.field('total')!.type,
        'common.v1.Money',
      );
    });

    test('are resolved by the path of the file that imports them', () {
      final result = _compile(<ProtoSource>[
        ProtoSource('common.proto', _common),
        ProtoSource('shop/orders.proto', '''
syntax = "proto3";

package orders.v1;

import "../common.proto";

message Order {
  common.v1.Money total = 1;
}
'''),
      ]);

      expect(result.warnings.where((w) => w.contains('not a file')), isEmpty);
    });

    test('are reported when the type of a file is used without them', () {
      expect(
        () => _compile(<ProtoSource>[
          ProtoSource('common.proto', _common),
          ProtoSource('orders.proto', '''
syntax = "proto3";

package orders.v1;

message Order {
  common.v1.Money total = 1;
}
'''),
        ]),
        throwsA(
          isA<ContractCompileException>().having(
            (error) => error.problems.join('\n'),
            'problems',
            contains('is not imported'),
          ),
        ),
      );
    });

    test('are reported when they are not used', () {
      final result = _compile(<ProtoSource>[
        ProtoSource('common.proto', _common),
        ProtoSource('orders.proto', '''
syntax = "proto3";

package orders.v1;

import "common.proto";

message Order {
  string id = 1;
}
'''),
      ]);

      expect(
        result.warnings.where((w) => w.contains('is not used')),
        hasLength(1),
      );
    });

    test('of a public import pass the types to the files that import them', () {
      final result = _compile(<ProtoSource>[
        ProtoSource('common.proto', _common),
        ProtoSource('prices.proto', '''
syntax = "proto3";

package prices.v1;

import public "common.proto";

message Price {
  common.v1.Money amount = 1;
}
'''),
        ProtoSource('orders.proto', '''
syntax = "proto3";

package orders.v1;

import "prices.proto";

message Order {
  common.v1.Money total = 1;
}
'''),
      ]);

      expect(result.warnings.where((w) => w.contains('not imported')), isEmpty);
      expect(
        result.contract.message('orders.v1.Order')!.field('total')!.type,
        'common.v1.Money',
      );
    });

    test('of the well-known types are known', () {
      final result = _compile(<ProtoSource>[
        ProtoSource('orders.proto', '''
syntax = "proto3";

package orders.v1;

import "google/protobuf/timestamp.proto";

message Order {
  google.protobuf.Timestamp placed_at = 1;
}
'''),
      ]);

      expect(result.warnings, isEmpty);
      expect(
        result.contract.message('orders.v1.Order')!.field('placed_at')!.type,
        'google.protobuf.Timestamp',
      );
    });

    test('of the well-known types have to be there', () {
      expect(
        () => _compile(<ProtoSource>[
          ProtoSource('orders.proto', '''
syntax = "proto3";

package orders.v1;

message Order {
  google.protobuf.Timestamp placed_at = 1;
}
'''),
        ]),
        throwsA(
          isA<ContractCompileException>().having(
            (error) => error.problems.join('\n'),
            'problems',
            contains('google/protobuf/timestamp.proto'),
          ),
        ),
      );
    });

    test('are written as the import of the generated file', () {
      final result = _compile(<ProtoSource>[
        ProtoSource('common.proto', _common),
        ProtoSource('orders.proto', _orders),
      ]);

      final orders = result.files.firstWhere(
        (file) => file.path == 'orders.pb.dart',
      );

      expect(orders.content, contains("import 'common.pb.dart';"));
    });
  });
}
