import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

const String _source = '''
syntax = "proto3";

package shop.v1;

// An order of a shop.
message Order {
  // Stable identifier of the order.
  string id = 1;

  // A line of the order.
  message Line {
    string sku = 1;
    int32 count = 2;
  }

  // The state of the order.
  enum State {
    ORDER_STATE_NEW = 0;
    ORDER_STATE_DONE = 1;
  }

  Line line = 2;
  State state = 3;

  // The quantities of the order, by the sku.
  map<string, int32> quantities = 4;

  // How the order is paid.
  oneof payment {
    string card_token = 5;
    string iban = 6;
  }
}
''';

ProtoFile _parse([String source = _source]) =>
    ProtoParser(source, fileName: 'shop.proto').parse();

CompileResult _compile([String source = _source]) =>
    ContractCompiler().compile(<ProtoSource>[
      ProtoSource('shop.proto', source),
    ]);

void main() {
  group('the parser', () {
    test('parses a group of a oneof', () {
      final file = _parse();

      final order = file.messages.first;
      expect(order.oneofs, hasLength(1));

      final group = order.oneofs.first;
      expect(group.name, 'payment');
      expect(group.fields.map((field) => field.name), <String>[
        'card_token',
        'iban',
      ]);
      expect(group.fields.first.number, 5);
      expect(group.fields.first.oneof, 'payment');
      expect(group.fields.first.optional, isTrue);
    });

    test('parses a map field', () {
      final file = _parse();

      final quantities = file.messages.first.field('quantities')!;
      expect(quantities.isMap, isTrue);
      expect(quantities.mapKeyType, 'string');
      expect(quantities.mapValueType, 'int32');
      expect(quantities.type, 'map');
    });

    test('parses a message and an enum declared inside a message', () {
      final file = _parse();

      expect(file.messages.map((message) => message.name), <String>[
        'Order',
        'Line',
      ]);
      expect(file.messages[1].scope, 'Order');
      expect(file.messages[1].fullName, 'shop.v1.Order.Line');
      expect(file.messages[1].dartName, 'OrderLine');

      expect(file.enums.single.name, 'State');
      expect(file.enums.single.scope, 'Order');
      expect(file.enums.single.dartName, 'OrderState');
    });

    test('resolves a type with the scope it was declared in', () {
      final file = _parse();

      final order = file.messages.first;
      expect(order.field('line')!.type, 'shop.v1.Order.Line');
      expect(order.field('state')!.type, 'shop.v1.Order.State');
    });

    test('keeps the fields of a oneof out of the fields of the message', () {
      final file = _parse();

      final order = file.messages.first;
      expect(order.fields.map((field) => field.name), <String>[
        'id',
        'line',
        'state',
        'quantities',
      ]);
      expect(order.allFields, hasLength(6));
      expect(order.field('iban'), isNotNull);
    });
  });

  group('the generator', () {
    late String code;

    setUp(() {
      code = _compile().files.single.content;
    });

    test('generates the class of a nested message', () {
      expect(code, contains('class OrderLine {'));
      expect(code, contains('final int count;'));
    });

    test('generates the enum of a nested enum', () {
      expect(code, contains('enum OrderState {'));
      expect(
        code,
        contains("orderStateDone('ORDER_STATE_DONE', number: 1)"),
      );
    });

    test('generates the group of a oneof as a sealed class', () {
      expect(code, contains('sealed class OrderPayment {'));
      expect(
          code, contains('class OrderPaymentCardToken extends OrderPayment'));
      expect(code, contains('class OrderPaymentIban extends OrderPayment'));
      expect(code, contains("String get memberName => 'cardToken';"));
    });

    test('generates a map field as a Dart map', () {
      expect(code, contains('final Map<String, int> quantities;'));
      expect(
        code,
        contains('this.quantities = const <String, int>{}'),
      );
    });

    test('writes a map as the entries of a message on the wire', () {
      expect(code, contains('entryWriter.writeString(1, entry.key);'));
      expect(code, contains('entryWriter.writeInt32(2, entry.value);'));
      expect(code, contains('writer.writeMessage(4, entryWriter.toBytes());'));
    });

    test('describes a map and a oneof in the OpenAPI document', () {
      final document = _compile().openapi;
      final schemas = (document['components']
          as Map<String, dynamic>)['schemas'] as Map<String, dynamic>;

      final order = schemas['Order'] as Map<String, dynamic>;
      final properties = order['properties'] as Map<String, dynamic>;

      final quantities = properties['quantities'] as Map<String, dynamic>;
      expect(quantities['type'], 'object');
      expect(
        (quantities['additionalProperties'] as Map<String, dynamic>)['type'],
        'integer',
      );

      expect(properties.containsKey('cardToken'), isTrue);
      expect(properties.containsKey('iban'), isTrue);
      expect(order['oneOf'], hasLength(1));
      expect(schemas.keys, contains('OrderLine'));
      expect(schemas.keys, contains('OrderState'));
    });
  });

  group('the difference between two contracts', () {
    test('a member that joins a oneof breaks the consumers', () {
      final base = _compile();
      final candidate = _compile(_source.replaceFirst(
        'string iban = 6;',
        'string iban = 6;\n    string cash = 7;',
      ));

      final diff = diffContracts(base.contract, candidate.contract);

      expect(diff.hasBreakingChanges, isTrue);
      expect(
        diff.breakingChanges.map((change) => change.message),
        contains('a field was added to the oneof'),
      );
    });

    test('a member that leaves a oneof breaks the consumers', () {
      final base = _compile();
      final candidate = _compile(_source.replaceFirst(
        '    string iban = 6;\n',
        '',
      ));

      final diff = diffContracts(base.contract, candidate.contract);

      expect(diff.hasBreakingChanges, isTrue);
      expect(
        diff.breakingChanges.map((change) => change.message),
        contains('member of the oneof was removed'),
      );
    });

    test('a type that is written with another qualifier is not a change', () {
      final base = _compile();
      final candidate = _compile(_source.replaceFirst(
        'Line line = 2;',
        'Order.Line line = 2;',
      ));

      final diff = diffContracts(base.contract, candidate.contract);

      expect(diff.breakingChanges, isEmpty);
    });
  });

  group('the linter', () {
    test('a group of a oneof is written in snake_case', () {
      final problems = lintContract(_contractOf('''
syntax = "proto3";

package shop.v1;

message Order {
  oneof PaymentSource {
    string card = 1;
  }
}
'''));

      expect(
        problems.map((problem) => problem.message),
        contains('A group of a oneof is written in snake_case.'),
      );
    });
  });
}

Contract _contractOf(String source) => Contract(<ProtoFile>[
      ProtoParser(source, fileName: 'shop.proto').parse(),
    ]);
