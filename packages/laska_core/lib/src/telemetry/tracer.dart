/// The tracing abstraction of Laska.
///
/// The runtime talks to a [Tracer] and never to a telemetry SDK directly, so
/// the OpenTelemetry implementation can be replaced without touching the
/// runtime. The OpenTelemetry implementation lives in `telemetry/otel.dart`.
library;

import 'dart:async';

/// The kind of a span.
///
/// The kinds follow the OpenTelemetry semantic conventions, so a backend can
/// tell a server span from a client span.
enum SpanKind {
  /// An internal operation of the service.
  internal,

  /// The service handles an incoming request.
  server,

  /// The service calls another service.
  client,

  /// The service publishes a message.
  producer,

  /// The service processes a message.
  consumer,
}

/// The identity of a span inside a trace.
///
/// The context is what travels between the services: it holds the id of the
/// trace and the id of the span, so a span created in another service becomes
/// the parent of the next one.
class SpanContext {
  /// Creates a span context.
  const SpanContext({
    required this.traceId,
    required this.spanId,
    this.sampled = true,
  });

  /// The id of the trace, shared by every span of the trace.
  final String traceId;

  /// The id of the span, unique inside the trace.
  final String spanId;

  /// Whether the trace is recorded by the backend.
  final bool sampled;

  /// The value of the `traceparent` header of this context.
  ///
  /// The format is the one of the W3C trace context specification:
  /// `00-{traceId}-{spanId}-{flags}`.
  String toTraceParent() => '00-$traceId-$spanId-${sampled ? '01' : '00'}';

  /// Reads a context out of the value of a `traceparent` header.
  ///
  /// Returns `null` when the value is missing or malformed.
  static SpanContext? parseTraceParent(String? value) {
    if (value == null) {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 4) {
      return null;
    }
    if (parts[0].length != 2 ||
        parts[1].length != 32 ||
        parts[2].length != 16 ||
        parts[3].length != 2) {
      return null;
    }
    if (parts[1] == '00000000000000000000000000000000' ||
        parts[2] == '0000000000000000') {
      return null;
    }
    return SpanContext(
      traceId: parts[1],
      spanId: parts[2],
      sampled: parts[3] != '00',
    );
  }

  @override
  String toString() => '$traceId/$spanId';

  @override
  bool operator ==(Object other) =>
      other is SpanContext &&
      other.traceId == traceId &&
      other.spanId == spanId;

  @override
  int get hashCode => Object.hash(traceId, spanId);
}

/// A span of a trace.
///
/// A span is created by a [Tracer], gets attributes while the work is done and
/// is ended exactly once. Ending a span twice is a no-op.
abstract class Span {
  /// The context of the span, used as the parent of the child spans.
  SpanContext get context;

  /// Sets an attribute of the span.
  void setAttribute(String name, Object? value);

  /// Records an error on the span.
  void recordError(Object error, [StackTrace? stackTrace]);

  /// Ends the span.
  void end();
}

/// Creates spans and propagates the trace context.
abstract class Tracer {
  /// Starts a span named [name].
  ///
  /// The span becomes a child of [parent]. When [parent] is `null`, the span
  /// of the work being done right now is used, so a span created inside a
  /// request belongs to the trace of that request.
  Span startSpan(
    String name, {
    SpanContext? parent,
    Map<String, Object?> attributes = const <String, Object?>{},
    SpanKind kind = SpanKind.internal,
  });

  /// Reads the trace context out of the headers of an incoming request.
  ///
  /// Returns `null` when the headers carry no trace context.
  SpanContext? extract(Map<String, String> headers);

  /// Writes the trace context into the headers of an outgoing request.
  void inject(SpanContext context, Map<String, String> headers);
}

/// A span that records nothing.
class NoopSpan implements Span {
  /// Creates a span without a context.
  NoopSpan() : context = const SpanContext(traceId: '', spanId: '');

  @override
  final SpanContext context;

  @override
  void setAttribute(String name, Object? value) {}

  @override
  void recordError(Object error, [StackTrace? stackTrace]) {}

  @override
  void end() {}
}

/// A tracer that records nothing.
///
/// It is the default of a service that does not export any telemetry, so the
/// instrumentation of the runtime costs nothing when it is not used.
class NoopTracer implements Tracer {
  /// Creates a tracer that records nothing.
  const NoopTracer();

  @override
  Span startSpan(
    String name, {
    SpanContext? parent,
    Map<String, Object?> attributes = const <String, Object?>{},
    SpanKind kind = SpanKind.internal,
  }) =>
      NoopSpan();

  @override
  SpanContext? extract(Map<String, String> headers) => null;

  @override
  void inject(SpanContext context, Map<String, String> headers) {}
}

final Object _currentSpanKey = Object();

/// The span of the work being done right now.
///
/// It is `null` outside of a request. The framework uses it to attach the
/// spans of the database and of the outgoing calls to the trace of the
/// request that caused them.
Span? get currentSpan {
  final value = Zone.current[_currentSpanKey];
  return value is Span ? value : null;
}

/// Runs [body] with [span] as the current span.
Future<T> runWithSpan<T>(Span? span, Future<T> Function() body) {
  return runZoned(body, zoneValues: <Object, Object?>{_currentSpanKey: span});
}
