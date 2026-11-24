/// The lifecycle of an application.
///
/// The lifecycle is the part of the framework that owns the resources of the
/// service: the hooks registered on the application are called by the server
/// in a fixed order, so a service warms its cache on the start, announces that
/// it is ready and releases its resources on the shutdown.
library;

import 'dart:async';

/// A hook of the lifecycle of an application.
///
/// A hook may be synchronous or asynchronous; the runtime awaits it.
typedef LifecycleHook = FutureOr<void> Function();

/// The phases of the lifecycle of an application.
enum LifecyclePhase {
  /// The application is starting: the resources are acquired.
  ///
  /// The hooks run before the server binds the port, so a hook that fails
  /// keeps the service from accepting traffic.
  start,

  /// The application is ready: it answers the traffic.
  ///
  /// The hooks run after the server bound the port and after the gRPC server
  /// of the service is up.
  ready,

  /// The application is stopping: the resources are released.
  ///
  /// The hooks run after the requests in flight finished, so the resources
  /// they release are still alive while the last answers are written.
  shutdown,
}

/// The hooks of one application, grouped by the phase they run in.
///
/// The hooks of a phase run in the order they were registered. A hook that
/// throws stops the phase, unless the caller gives an [onError] callback: then
/// the error is reported and the next hook runs.
class Lifecycle {
  /// Creates an empty lifecycle.
  Lifecycle();

  final Map<LifecyclePhase, List<LifecycleHook>> _hooks =
      <LifecyclePhase, List<LifecycleHook>>{
    LifecyclePhase.start: <LifecycleHook>[],
    LifecyclePhase.ready: <LifecycleHook>[],
    LifecyclePhase.shutdown: <LifecycleHook>[],
  };

  /// Registers [hook] in [phase].
  void add(LifecyclePhase phase, LifecycleHook hook) {
    _hooks[phase]!.add(hook);
  }

  /// The hooks registered in [phase], in the order they run.
  List<LifecycleHook> hooksOf(LifecyclePhase phase) =>
      List<LifecycleHook>.unmodifiable(_hooks[phase]!);

  /// Runs the hooks of [phase] in the order they were registered.
  ///
  /// A hook that throws stops the run and the error is rethrown, unless
  /// [onError] is given: then the error is passed to it and the next hook
  /// runs. The shutdown phase uses that, because a resource that fails to
  /// close must not keep the other resources open.
  Future<void> run(
    LifecyclePhase phase, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    for (final hook in List<LifecycleHook>.of(_hooks[phase]!)) {
      try {
        await hook();
      } catch (error, stackTrace) {
        if (onError == null) {
          rethrow;
        }
        onError(error, stackTrace);
      }
    }
  }
}
