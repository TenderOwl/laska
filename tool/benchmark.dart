import 'dart:async';
import 'dart:io';

import 'package:laska_core/laska_core.dart';

/// Measures the hot path of the runtime: the routing of a request and the
/// dispatch of that request to its handler.
///
/// The benchmark runs in process, so it measures the framework and not the
/// network. The numbers are relative: they tell how much a change of the hot
/// path costs, not how fast a service is on a given machine.
///
/// Usage: `dart run tool/benchmark.dart [iterations]`
Future<void> main(List<String> arguments) async {
  final iterations =
      arguments.isEmpty ? 200000 : (int.tryParse(arguments.first) ?? 200000);

  final app = _application();

  // The first calls pay for the tables of the router and for the compilation
  // of the code, so they are not part of the measurement.
  for (var index = 0; index < 1000; index++) {
    await _dispatchStatic(app);
    await _dispatchParameter(app);
    app.router.lookup('GET', '/v1/users/42');
  }

  await _measure(
    'router: a static route',
    iterations,
    () => app.router.lookup('GET', '/v1/users'),
  );

  await _measure(
    'router: a route with a parameter',
    iterations,
    () => app.router.lookup('GET', '/v1/users/42'),
  );

  await _measure(
    'router: a route with a constraint',
    iterations,
    () => app.router.lookup('GET', '/v1/orders/42'),
  );

  await _measure(
    'dispatch: a static route',
    iterations,
    () => _dispatchStatic(app),
  );

  await _measure(
    'dispatch: a route with a parameter',
    iterations,
    () => _dispatchParameter(app),
  );
}

/// The application the benchmark runs against.
///
/// It holds the middleware of a real service — the request id, the tracing,
/// the metrics and the log — so the measurement covers the whole chain.
Laska _application() {
  final app = Laska();

  app.use(requestIdMiddleware());
  app.use(tracingMiddleware(const NoopTracer()));
  app.use(metricsMiddleware(MetricsRegistry()));

  app.get('/v1/users', (ctx) => ctx.json(<String, Object?>{'id': 'u_1'}));
  app.get('/v1/users/:id', (ctx) => ctx.json(<String, Object?>{'id': 'u_1'}));
  app.get(
      '/v1/orders/:id<int>', (ctx) => ctx.json(<String, Object?>{'id': 'o_1'}));

  return app;
}

/// Dispatches a request to a static route.
Future<Response> _dispatchStatic(Laska app) => app.dispatcher.dispatch(
      _request('/v1/users'),
    );

/// Dispatches a request to a route with a parameter.
Future<Response> _dispatchParameter(Laska app) => app.dispatcher.dispatch(
      _request('/v1/users/42'),
    );

/// Builds a request like the server builds one.
Request _request(String path) => Request(
      method: 'GET',
      path: path,
      uri: 'http://127.0.0.1:8080$path',
      query: const <String, String>{},
      headers: const <String, String>{'accept': 'application/json'},
    );

/// Runs [body] [iterations] times and reports what it cost.
Future<void> _measure(
  String label,
  int iterations,
  FutureOr<Object?> Function() body,
) async {
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    await body();
  }
  stopwatch.stop();

  final micros = stopwatch.elapsedMicroseconds / iterations;
  final perSecond = iterations * 1000000 / stopwatch.elapsedMicroseconds;

  stdout.writeln(
    '${label.padRight(34)} '
    '${micros.toStringAsFixed(2).padLeft(9)} us/op  '
    '${perSecond.toStringAsFixed(0).padLeft(10)} op/s',
  );
}
