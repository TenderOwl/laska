import 'dart:async';
import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('laska_supervisor_');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  String fixturePath() => File('test/fixtures/worker.dart').absolute.path;

  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'The condition was not met in time. '
          'Files: ${directory.listSync().map((entry) => entry.path).toList()}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  int reportCount() => directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.txt'))
      .length;

  group('Supervisor', () {
    test('uses the number of cores by default', () {
      final supervisor = Supervisor(
        SupervisorOptions(
          entrypoint: fixturePath(),
          executable: Platform.resolvedExecutable,
        ),
      );

      expect(
        supervisor.workerCount,
        Platform.numberOfProcessors.clamp(1, 8),
      );
    });

    test('uses the configured number of workers', () {
      final supervisor = Supervisor(
        SupervisorOptions(
          entrypoint: fixturePath(),
          executable: Platform.resolvedExecutable,
          workers: 3,
        ),
      );

      expect(supervisor.workerCount, 3);
    });

    test('starts the workers and passes the environment', () async {
      final supervisor = Supervisor(
        SupervisorOptions(
          entrypoint: fixturePath(),
          executable: Platform.resolvedExecutable,
          workers: 2,
          address: '127.0.0.1',
          port: 4321,
          environment: <String, String>{'LASKA_TEST_OUTPUT': directory.path},
          logger: Logger(sink: (_) {}),
        ),
      );

      final run = supervisor.run();
      addTearDown(() async {
        await supervisor.stop();
        await run;
      });

      await waitFor(() => reportCount() >= 2);

      expect(
        File('${directory.path}/worker-0.txt').readAsStringSync().trim(),
        '0 4321 127.0.0.1',
      );
      expect(
        File('${directory.path}/worker-1.txt').readAsStringSync().trim(),
        '1 4321 127.0.0.1',
      );
      expect(supervisor.runningWorkers, 2);
    });

    test('stops every worker', () async {
      final supervisor = Supervisor(
        SupervisorOptions(
          entrypoint: fixturePath(),
          executable: Platform.resolvedExecutable,
          workers: 2,
          port: 4322,
          environment: <String, String>{'LASKA_TEST_OUTPUT': directory.path},
          logger: Logger(sink: (_) {}),
        ),
      );

      final run = supervisor.run();
      addTearDown(() async {
        await supervisor.stop();
        await run;
      });

      await waitFor(() => reportCount() >= 2);

      await supervisor.stop();
      await run;

      expect(supervisor.runningWorkers, 0);
    });
  });
}
