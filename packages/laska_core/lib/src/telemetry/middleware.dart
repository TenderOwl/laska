/// The built-in instrumentation of the runtime.
///
/// Tracing and metrics are implemented as middleware, so they cover every
/// request of the service without a line of code in the service itself.
library;

import '../middleware.dart';
import 'metrics.dart';
import 'tracer.dart';

/// Creates a span for every request.
///
/// The span is a child of the trace the caller sent in the `traceparent`
/// header, so a request through two services shows up as one trace. The span
/// is the current span while the request is handled, so the spans of the
/// database and of the outgoing calls belong to the same trace.
Middleware tracingMiddleware(
  Tracer tracer, {
  String spanName = 'http.server',
}) {
  return (request, next) async {
    final parent = tracer.extract(request.headers);
    final span = tracer.startSpan(
      spanName,
      parent: parent,
      kind: SpanKind.server,
      attributes: <String, Object?>{
        'http.request.method': request.method,
        'url.path': request.path,
        'http.route': request.routePattern ?? request.path,
      },
    );
    request.traceContext = span.context;

    try {
      final response = await runWithSpan(span, next);
      span.setAttribute('http.response.status_code', response.status);
      return response;
    } catch (error, stackTrace) {
      span.recordError(error, stackTrace);
      rethrow;
    } finally {
      span.end();
    }
  };
}

/// Records the number and the duration of the requests.
///
/// The route of the template is used as a label, not the path of the request,
/// so the number of the label values stays small.
Middleware metricsMiddleware(Meter meter, {String prefix = 'laska'}) {
  final requests = meter.counter(
    '${prefix}_http_requests_total',
    description: 'The number of the HTTP requests.',
  );
  final duration = meter.histogram(
    '${prefix}_http_request_duration_seconds',
    description: 'The duration of the HTTP requests.',
    unit: 's',
  );

  return (request, next) async {
    final stopwatch = Stopwatch()..start();
    final labels = <String, String>{
      'method': request.method,
      'route': request.routePattern ?? request.path,
    };

    try {
      final response = await next();
      requests
          .add(1, <String, String>{...labels, 'status': '${response.status}'});
      duration.record(stopwatch.elapsedMicroseconds / 1000000, labels);
      return response;
    } catch (_) {
      requests.add(1, <String, String>{...labels, 'status': 'error'});
      duration.record(stopwatch.elapsedMicroseconds / 1000000, labels);
      rethrow;
    }
  };
}
