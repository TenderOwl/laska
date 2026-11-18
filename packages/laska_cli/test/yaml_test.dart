import 'package:laska_cli/src/yaml.dart';
import 'package:test/test.dart';

void main() {
  group('parseYaml', () {
    test('reads a map of scalars', () {
      final document = parseYaml('''
name: users
port: 8080
enabled: true
''');

      expect(document, <String, Object?>{
        'name': 'users',
        'port': '8080',
        'enabled': 'true',
      });
    });

    test('reads a nested map', () {
      final document = parseYaml('''
environment:
  LOG_LEVEL: debug
  DATABASE_URL: postgres://localhost/users
''');

      expect(document, <String, Object?>{
        'environment': <String, Object?>{
          'LOG_LEVEL': 'debug',
          'DATABASE_URL': 'postgres://localhost/users',
        },
      });
    });

    test('reads a list of scalars', () {
      final document = parseYaml('''
depends_on:
  - users
  - billing
''');

      expect(document, <String, Object?>{
        'depends_on': <Object?>['users', 'billing'],
      });
    });

    test('reads a list of maps', () {
      final document = parseYaml('''
services:
  - name: users
    entrypoint: bin/server.dart
    port: 8080
  - name: orders
    entrypoint: bin/orders.dart
    port: 8081
''');

      expect(document, <String, Object?>{
        'services': <Object?>[
          <String, Object?>{
            'name': 'users',
            'entrypoint': 'bin/server.dart',
            'port': '8080',
          },
          <String, Object?>{
            'name': 'orders',
            'entrypoint': 'bin/orders.dart',
            'port': '8081',
          },
        ],
      });
    });

    test('reads a map inside a list item', () {
      final document = parseYaml('''
services:
  - name: users
    environment:
      LOG_LEVEL: debug
    port: 8080
''');

      final services = (document as Map)['services'] as List;
      expect(services.single, <String, Object?>{
        'name': 'users',
        'environment': <String, Object?>{'LOG_LEVEL': 'debug'},
        'port': '8080',
      });
    });

    test('reads an inline list', () {
      final document = parseYaml('depends_on: [users, billing]\n');

      expect(document, <String, Object?>{
        'depends_on': <Object?>['users', 'billing'],
      });
    });

    test('reads an empty inline list', () {
      final document = parseYaml('depends_on: []\n');

      expect(document, <String, Object?>{
        'depends_on': <Object?>[],
      });
    });

    test('ignores the comments and the empty lines', () {
      final document = parseYaml('''
# the services of the workspace

services:
  # the users service
  - name: users
''');

      expect(document, <String, Object?>{
        'services': <Object?>[
          <String, Object?>{'name': 'users'},
        ],
      });
    });

    test('removes the quotes of a value', () {
      final document = parseYaml('''
name: "users"
entrypoint: 'bin/server.dart'
''');

      expect(document, <String, Object?>{
        'name': 'users',
        'entrypoint': 'bin/server.dart',
      });
    });

    test('keeps a colon that is inside a value', () {
      final document = parseYaml('url: postgres://localhost:5432/users\n');

      expect(document, <String, Object?>{
        'url': 'postgres://localhost:5432/users',
      });
    });

    test('reads an empty document', () {
      expect(parseYaml(''), isNull);
      expect(parseYaml('# only a comment\n'), isNull);
    });

    test('fails on a line that is not a pair', () {
      expect(
        () => parseYaml('services\n'),
        throwsA(isA<YamlException>()),
      );
    });

    test('fails on an anchor', () {
      expect(
        () => parseYaml('name: &anchor users\n'),
        throwsA(isA<YamlException>()),
      );
    });

    test('fails on an unexpected indentation', () {
      expect(
        () => parseYaml('''
name: users
  port: 8080
'''),
        throwsA(isA<YamlException>()),
      );
    });

    test('reads the keys of a list item whatever their indentation is', () {
      final document = parseYaml('''
services:
  - name: users
        port: 8080
''');

      final services = (document as Map)['services'] as List;
      expect(services.single, <String, Object?>{
        'name': 'users',
        'port': '8080',
      });
    });
  });
}
