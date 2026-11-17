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
    this.environment = const <String, String>{},
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

  /// Extra environment variables given to every worker.
  ///
  /// The variables of the supervisor are inherited, so a worker sees the
  /// configuration of the service.
  final Map<String, String> environment;

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
  bool _shuttingDown = false;
  Completer<void>? _finished;

  /// The number of workers to start.
  int get workerCount {
    final configured = options.workers;
    if (configured != null) {
      return configured;
    }
    return Platform.numberOfProcessors.clamp(1, 8);
  }

  /// The number of workers that are currently running.
  int get runningWorkers => _workers.length;

  /// Starts the workers and waits until the supervisor is stopped.
  Future<void> run() async {
    final finished = Completer<void>();
    _finished = finished;

    options.logger?.info(
      'starting $workerCount worker(s) on ${options.address}:${options.port}',
    );

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
    );

    _workers[id] = process;

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
    stdout.writeln('[$id] $line');
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
