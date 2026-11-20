import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'logger.dart';

/// The environment variable that marks a process as a worker.
const String workerEnvironmentKey = 'LASKA_WORKER';

/// The environment variable holding the id of a worker.
const String workerIdEnvironmentKey = 'LASKA_WORKER_ID';

/// The environment variable holding the port the workers bind to.
const String workerPortEnvironmentKey = 'LASKA_PORT';

/// The environment variable holding the address the workers bind to.
const String workerAddressEnvironmentKey = 'LASKA_ADDRESS';

/// Options of the supervisor.
class SupervisorOptions {
  /// Creates supervisor options.
  const SupervisorOptions({
    required this.entrypoint,
    required this.executable,
    this.workers,
    this.address = '0.0.0.0',
    this.port = 3789,
    this.drainTimeout = const Duration(seconds: 30),
    this.restartDelay = const Duration(seconds: 1),
    this.maxRestarts = 5,
    this.environment = const <String, String>{},
    this.workingDirectory,
    this.label,
    this.logger,
  });

  /// The Dart file every worker runs.
  final String entrypoint;

  /// The executable the workers are started with.
  final String executable;

  /// The number of workers. Defaults to the number of cores, capped at eight.
  final int? workers;

  /// The address the workers bind to.
  final String address;

  /// The port the workers bind to.
  final int port;

  /// How long a worker may take to shut down before it is killed.
  final Duration drainTimeout;

  /// How long the supervisor waits before restarting a crashed worker.
  final Duration restartDelay;

  /// How often a worker may be restarted before the supervisor gives up.
  ///
  /// The counter is reset when a worker ran long enough, so a worker that
  /// crashes once in a while is not abandoned.
  final int maxRestarts;

  /// Extra environment variables given to every worker.
  ///
  /// The variables of the supervisor are inherited, so a worker sees the
  /// configuration of the service.
  final Map<String, String> environment;

  /// The directory the workers are started in.
  ///
  /// The value is `null` when the workers inherit the directory of the
  /// supervisor. A service is usually started in the directory of its own
  /// package, so the paths of the service are read against it.
  final String? workingDirectory;

  /// The label written in front of the log lines of the workers.
  ///
  /// It tells the logs of the services of a workspace apart.
  final String? label;

  /// The logger of the supervisor.
  final Logger? logger;
}

/// Runs an application in several worker processes.
///
/// The supervisor starts [SupervisorOptions.workers] processes of the same
/// entrypoint. Every worker binds the same port with a shared socket, so the
/// kernel distributes the connections between them. A worker that dies is
/// restarted; on SIGINT or SIGTERM the supervisor asks every worker to shut
/// down and waits for them to finish their requests.
class Supervisor {
  /// Creates a supervisor.
  Supervisor(this.options);

  /// The options of the supervisor.
  final SupervisorOptions options;

  final Map<int, Process> _workers = <int, Process>{};
  final Map<int, int> _failures = <int, int>{};
  final Map<int, DateTime> _startedAt = <int, DateTime>{};
  bool _shuttingDown = false;
  Completer<void>? _finished;

  /// The number of workers to start.
  int get workerCount {
    final configured = options.workers;
    if (configured != null) {
      return configured;
    }
    if (!supportsSharedPort) {
      // The platform has no SO_REUSEPORT, so two processes cannot bind the
      // same port. The service runs with a single worker there.
      return 1;
    }
    return Platform.numberOfProcessors.clamp(1, 8);
  }

  /// Whether the platform lets several processes bind the same port.
  ///
  /// POSIX systems have SO_REUSEPORT, so the kernel balances the connections
  /// between the workers. Windows has no such option: two processes cannot
  /// listen on the same port, so the service runs with a single worker.
  static bool get supportsSharedPort => !Platform.isWindows;

  /// The number of workers that are currently running.
  int get runningWorkers => _workers.length;

  /// The workers the supervisor gave up on, because they kept crashing.
  List<int> get abandonedWorkers => _failures.entries
      .where((entry) => entry.value > options.maxRestarts)
      .map((entry) => entry.key)
      .toList();

  /// Starts the workers and waits until the supervisor is stopped.
  Future<void> run() async {
    final finished = Completer<void>();
    _finished = finished;

    options.logger?.info(
      'starting $workerCount worker(s) on ${options.address}:${options.port}',
    );

    if (workerCount > 1 && !supportsSharedPort) {
      options.logger?.warning(
        'This platform cannot share a port between processes, so only one '
        'worker can listen on ${options.address}:${options.port}.',
      );
    }

    for (var id = 0; id < workerCount; id++) {
      await _startWorker(id);
    }

    _installSignalHandlers();

    // Keep the supervisor alive until it is asked to stop.
    await finished.future;
  }

  /// Stops every worker.
  Future<void> stop() async {
    if (_shuttingDown) {
      return;
    }
    _shuttingDown = true;
    options.logger?.info('stopping workers');

    final exits = <Future<int>>[];
    for (final process in _workers.values) {
      _kill(process, ProcessSignal.sigterm);
      exits.add(process.exitCode);
    }

    await Future.wait(exits).timeout(
      options.drainTimeout,
      onTimeout: () => const <int>[],
    );

    for (final process in _workers.values) {
      _kill(process, ProcessSignal.sigkill);
    }
    _workers.clear();

    final finished = _finished;
    if (finished != null && !finished.isCompleted) {
      finished.complete();
    }
  }

  void _kill(Process process, ProcessSignal signal) {
    try {
      process.kill(signal);
    } catch (_) {
      // The process is already gone, or the platform does not know the signal.
    }
  }

  Future<void> _startWorker(int id) async {
    final environment = <String, String>{
      ...Platform.environment,
      ...options.environment,
      workerEnvironmentKey: '1',
      workerIdEnvironmentKey: '$id',
      workerPortEnvironmentKey: '${options.port}',
      workerAddressEnvironmentKey: options.address,
    };

    final process = await Process.start(
      options.executable,
      <String>[options.entrypoint],
      environment: environment,
      includeParentEnvironment: false,
      workingDirectory: options.workingDirectory,
    );

    _workers[id] = process;
    _startedAt[id] = DateTime.now();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _forward(id, line));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _forward(id, line));

    unawaited(
      process.exitCode.then((code) async {
        _workers.remove(id);
        if (_shuttingDown) {
          return;
        }

        final uptime =
            DateTime.now().difference(_startedAt[id] ?? DateTime.now());
        final failures =
            uptime > const Duration(minutes: 1) ? 1 : (_failures[id] ?? 0) + 1;
        _failures[id] = failures;

        if (failures > options.maxRestarts) {
          options.logger?.error(
            'worker $id failed $failures times in a row, the supervisor '
            'gives up on it',
          );
          return;
        }

        options.logger?.warning('worker $id exited with code $code');
        await Future<void>.delayed(options.restartDelay);
        if (!_shuttingDown) {
          await _startWorker(id);
        }
      }),
    );
  }

  void _forward(int id, String line) {
    options.logger?.debug('worker $id: $line');
    final label = options.label;
    stdout.writeln(label == null ? '[$id] $line' : '[$label $id] $line');
  }

  void _installSignalHandlers() {
    Future<void> handle() async {
      await stop();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen((_) => handle());
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => handle());
    }
  }
}
