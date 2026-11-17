import 'dart:io';

/// A worker that fails at once.
///
/// The supervisor test uses it to check that a worker which keeps crashing is
/// abandoned instead of restarted forever.
void main() {
  stderr.writeln('worker failed to start');
  exit(1);
}
