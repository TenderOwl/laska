import 'dart:async';
import 'dart:io';

/// A worker that reports its environment and then stays alive.
///
/// The supervisor test uses it to check that every worker gets its own id,
/// the address and the port of the service.
Future<void> main() async {
  final directory = Platform.environment['LASKA_TEST_OUTPUT'];
  final id = Platform.environment['LASKA_WORKER_ID'] ?? '?';
  final port = Platform.environment['LASKA_PORT'] ?? '?';
  final address = Platform.environment['LASKA_ADDRESS'] ?? '?';

  if (directory != null) {
    File('$directory/worker-$id.txt').writeAsStringSync('$id $port $address\n');
  }

  stdout.writeln('worker $id ready');

  // A timer keeps the isolate alive until the worker is stopped.
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
