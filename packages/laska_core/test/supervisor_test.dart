import 'dart:async';
import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('laska_supervisor_');
  });

  /// Deletes the [directory] when the system lets it go.
  ///
  /// A worker that runs in a directory holds it while it lives, and the system
  /// may hold it for a moment after it stops.
  Future<void> deleteDirectory(Directory directory) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (!directory.existsSync()) {
        return;
      }
      try {
        directory.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  tearDown(() async {
    await deleteDirectory(directory);
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

  /// The report of the worker [worker], empty while it has none.
  ///
  /// The worker writes the report itself, so the file can be seen in the
  /// directory before it holds anything. The report is complete when it ends
  /// with the line feed the worker writes.
  String report(int worker) {
    final file = File('${directory.path}/worker-$worker.txt');
    if (!file.existsSync()) {
      return '';
    }
    return file.readAsStringSync();
  }

  /// The lines of the report of the worker [worker].
  List<String> reportLines(int worker) => report(worker).trim().split('\n');

  group('Supervisor', () {
    test('uses the number of cores by default', () {
      final supervisor = Supervisor(
        SupervisorOptions(
          entrypoint: fixturePath(),
          executable: Platform.resolvedExecutable,
        ),
      );

      if (Supervisor.supportsSharedPort) {
        expect(
          supervisor.workerCount,
          Platform.numberOfProcessors.clamp(1, 8),
        );
      } else {
        expect(supervisor.workerCount, 1);
      }
    });

    test('knows whether the platform shares a port', () {
      expect(Supervisor.supportsSharedPort, isNot(Platform.isWindows));
    });

    test('gives up on a worker that keeps crashing', () async {
      final supervisor = Supervisor(
        SupervisorOptions(
          entrypoint: File('test/fixtures/crashing_worker.dart').absolute.path,
          executable: Platform.resolvedExecutable,
          workers: 1,
          maxRestarts: 1,
          restartDelay: const Duration(milliseconds: 50),
          logger: Logger(sink: (_) {}),
        ),
      );

      final run = supervisor.run();
      addTearDown(() async {
        await supervisor.stop();
        await run;
      });

      await waitFor(() => supervisor.abandonedWorkers.isNotEmpty);

      expect(supervisor.abandonedWorkers, <int>[0]);
      expect(supervisor.runningWorkers, 0);
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

      await waitFor(
        () => report(0).endsWith('\n') && report(1).endsWith('\n'),
      );

      expect(reportLines(0).first, '0 4321 127.0.0.1');
      expect(reportLines(1).first, '1 4321 127.0.0.1');
      expect(supervisor.runningWorkers, 2);
    });

    test('starts the workers in the given directory', () async {
      // The directory of the worker is its own, so it is not the directory of
      // the reports: a worker that runs in it holds it while it lives.
      final work =
          Directory.systemTemp.createTempSync('laska_supervisor_work_');

      final supervisor = Supervisor(
        SupervisorOptions(
          entrypoint: fixturePath(),
          executable: Platform.resolvedExecutable,
          workers: 1,
          address: '127.0.0.1',
          port: 4323,
          environment: <String, String>{'LASKA_TEST_OUTPUT': directory.path},
          workingDirectory: work.path,
          logger: Logger(sink: (_) {}),
        ),
      );

      final run = supervisor.run();
      addTearDown(() async {
        await supervisor.stop();
        await run;
        await deleteDirectory(work);
      });

      await waitFor(() => report(0).endsWith('\n'));

      // The worker runs in the directory it was given, so the paths of the
      // service are read against its own package.
      final name = work.path.split(Platform.pathSeparator).last;
      expect(reportLines(0)[1], endsWith(name));
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
