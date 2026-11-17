/// The observability of a service.
///
/// One call wires the whole stack: the request ids, the tracing, the metrics,
/// the request log and the health probes. The service writes no
/// instrumentation code at all.
library;

import 'app.dart';
import 'health.dart';
import 'logger.dart';
import 'middleware/builtin.dart';
import 'response.dart';
import 'telemetry/metrics.dart';
import 'telemetry/middleware.dart';
import 'telemetry/otel.dart';
import 'telemetry/tracer.dart';

/// The observability of a service.
class Observability {
  /// Creates an observability stack.
  Observability({
    required this.tracer,
    required this.meter,
    required this.logger,
    required this.registry,
  });

  /// The tracer of the service.
  final Tracer tracer;

  /// The meter of the service.
  final Meter meter;

  /// The logger of the service.
  final Logger logger;

  /// The registry holding the metrics of the service.
  final MetricsRegistry registry;

  /// Wires the observability into [app].
  ///
  /// The middleware run in this order: the request id, the tracing, the
  /// metrics and the request log. The health probes and the `/metrics`
  /// endpoint are registered as routes.
  ///
  /// When no [tracer] is given, the OpenTelemetry SDK is used if the
  /// environment asks for it — `OTEL_SERVICE_NAME` or
  /// `OTEL_EXPORTER_OTLP_ENDPOINT` — and nothing is exported otherwise.
  static Future<Observability> install(
    Laska app, {
    Tracer? tracer,
    Meter? meter,
    MetricsRegistry? registry,
    Logger? logger,
    Future<bool> Function()? isReady,
    bool probes = true,
    bool metrics = true,
    String metricsPath = '/metrics',
  }) async {
    final metricsRegistry =
        registry ?? (meter is MetricsRegistry ? meter : MetricsRegistry());
    final effectiveMeter = meter ?? metricsRegistry;
    final effectiveLogger = logger ?? app.logger;
    final effectiveTracer = tracer ?? await _defaultTracer();

    app.logger = effectiveLogger;
    app.use(requestIdMiddleware());
    app.use(tracingMiddleware(effectiveTracer));
    app.use(metricsMiddleware(effectiveMeter));
    app.use(loggingMiddleware(effectiveLogger));

    if (probes) {
      registerHealthChecks(
        app,
        isReady: isReady ?? () => databaseReady(app.database),
      );
    }

    if (metrics) {
      app.get(
        metricsPath,
        (ctx) => Response.text(
          metricsRegistry.toPrometheus(),
          headers: <String, String>{
            'content-type': 'text/plain; version=0.0.4; charset=utf-8',
          },
        ),
      );
    }

    return Observability(
      tracer: effectiveTracer,
      meter: effectiveMeter,
      logger: effectiveLogger,
      registry: metricsRegistry,
    );
  }

  /// The tracer of the environment.
  ///
  /// The OpenTelemetry SDK is only started when the environment asks for it,
  /// so a service without a collector exports nothing and pays nothing.
  static Future<Tracer> _defaultTracer() async {
    final config = OtelConfig.fromEnvironment();
    if (config.disabled) {
      return const NoopTracer();
    }
    if (config.serviceName == null && config.endpoint == null) {
      return const NoopTracer();
    }
    return OtelTracer.create(config: config);
  }
}
