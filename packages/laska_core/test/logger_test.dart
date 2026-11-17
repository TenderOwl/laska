import 'dart:convert';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  late List<String> lines;

  setUp(() {
    lines = <String>[];
    Config.reset();
  });

  tearDown(() {
    Config.reset();
  });

  Map<String, Object?> record(String line) =>
      jsonDecode(line) as Map<String, Object?>;

  group('Logger', () {
    test('writes one JSON object per line', () {
      final logger = Logger(sink: lines.add);

      logger.info('service started');

      expect(lines, hasLength(1));
      final entry = record(lines.single);
      expect(entry['message'], 'service started');
      expect(entry['level'], 'info');
      expect(entry['service'], 'laska');
      expect(entry['time'], isA<String>());
    });

    test('writes the fields of a record', () {
      final logger = Logger(sink: lines.add);

      logger.info('request', <String, Object?>{'method': 'GET', 'status': 200});

      final entry = record(lines.single);
      expect(entry['method'], 'GET');
      expect(entry['status'], 200);
    });

    test('writes the version of the service', () {
      final logger =
          Logger(sink: lines.add, service: 'users', version: '1.2.3');

      logger.info('started');

      final entry = record(lines.single);
      expect(entry['service'], 'users');
      expect(entry['version'], '1.2.3');
    });

    test('skips the records below the level', () {
      final logger = Logger(sink: lines.add, level: LogLevel.warning);

      logger.debug('debug');
      logger.info('info');
      logger.warning('warning');

      expect(lines, hasLength(1));
      expect(record(lines.single)['message'], 'warning');
    });

    test('writes the error level', () {
      final logger = Logger(sink: lines.add);

      logger.error('failed');

      expect(record(lines.single)['level'], 'error');
    });

    test('redacts a secret field', () {
      final logger = Logger(sink: lines.add);

      logger.info('config', <String, Object?>{'password': 'hunter2'});

      expect(record(lines.single)['password'], '***');
    });

    test('redacts a secret field of a nested map', () {
      final logger = Logger(sink: lines.add);

      logger.info('config', <String, Object?>{
        'database': <String, Object?>{'password': 'hunter2'},
      });

      final database =
          record(lines.single)['database']! as Map<String, Object?>;
      expect(database['password'], '***');
    });

    test('keeps a normal field', () {
      final logger = Logger(sink: lines.add);

      logger.info('config', <String, Object?>{'port': 8080});

      expect(record(lines.single)['port'], 8080);
    });
  });
}
