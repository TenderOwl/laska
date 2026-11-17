import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('laska_config_');
    Config.reset();
  });

  tearDown(() {
    Config.reset();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  File writeEnv(String content) {
    final file = File('${directory.path}/.env');
    file.writeAsStringSync(content);
    return file;
  }

  group('Config', () {
    test('reads the values of a .env file', () {
      writeEnv('PORT=8080\nHOST=localhost\n');

      Config.loadDotEnv('${directory.path}/.env');

      expect(Config.string('PORT'), '8080');
      expect(Config.string('HOST'), 'localhost');
    });

    test('ignores comments and empty lines', () {
      writeEnv('# a comment\n\nPORT=8080\n');

      Config.loadDotEnv('${directory.path}/.env');

      expect(Config.string('PORT'), '8080');
    });

    test('removes the quotes of a value', () {
      writeEnv('TOKEN="abc"\nSECRET=\'xyz\'\n');

      Config.loadDotEnv('${directory.path}/.env');

      expect(Config.string('TOKEN'), 'abc');
      expect(Config.string('SECRET'), 'xyz');
    });

    test('ignores a missing file', () {
      Config.loadDotEnv('${directory.path}/missing.env');

      expect(Config.lookup('PORT'), isNull);
      expect(Config.string('PORT'), '');
    });

    test('keeps the value after the first equals sign', () {
      writeEnv('CONNECTION=postgres://user:pass@host/db?x=1\n');

      Config.loadDotEnv('${directory.path}/.env');

      expect(
        Config.string('CONNECTION'),
        'postgres://user:pass@host/db?x=1',
      );
    });

    test('prefers the environment over the file', () {
      final key = Platform.environment.keys.firstWhere(
        (name) => (Platform.environment[name] ?? '').isNotEmpty,
      );
      writeEnv('$key=from-file\n');

      Config.loadDotEnv('${directory.path}/.env');

      expect(Config.string(key), Platform.environment[key]);
    });

    test('falls back to the default value', () {
      expect(Config.string('MISSING', defaultValue: 'fallback'), 'fallback');
      expect(Config.integer('MISSING', defaultValue: 7), 7);
      expect(Config.number('MISSING', defaultValue: 1.5), 1.5);
      expect(Config.boolean('MISSING', defaultValue: true), isTrue);
      expect(
          Config.list('MISSING', defaultValue: <String>['a']), <String>['a']);
    });

    test('reads the typed values', () {
      writeEnv('PORT=8080\nRATE=1.5\nDEBUG=true\nTAGS=a, b ,c\n');

      Config.loadDotEnv('${directory.path}/.env');

      expect(Config.integer('PORT'), 8080);
      expect(Config.number('RATE'), 1.5);
      expect(Config.boolean('DEBUG'), isTrue);
      expect(Config.list('TAGS'), <String>['a', 'b', 'c']);
    });

    test('uses the default value for an unparsable number', () {
      writeEnv('PORT=not-a-number\n');

      Config.loadDotEnv('${directory.path}/.env');

      expect(Config.integer('PORT', defaultValue: 3000), 3000);
    });
  });

  group('Config secrets', () {
    test('redacts a secret value', () {
      writeEnv('API_KEY=super-secret\n');

      Config.loadDotEnv('${directory.path}/.env');
      final secret = Config.secret('API_KEY');

      expect(secret.value, 'super-secret');
      expect(secret.toString(), '***');
      expect(Config.redacted['API_KEY'], '***');
    });

    test('knows the secret keys by name', () {
      expect(Config.isSecret('password'), isTrue);
      expect(Config.isSecret('TOKEN'), isTrue);
      expect(Config.isSecret('api_key'), isTrue);
      expect(Config.isSecret('port'), isFalse);
    });

    test('marks a key as secret', () {
      Config.redact('DATABASE_URL');

      expect(Config.isSecret('database_url'), isTrue);
    });
  });
}
