/// The OpenTelemetry implementation of the tracing abstraction.
///
/// The runtime only knows the [Tracer] of `telemetry/tracer.dart`, so the
/// OpenTelemetry SDK can be replaced without touching the runtime. The
/// configuration follows the standard `OTEL_*` environment variables, so an
/// existing collector works without any Laska specific setup.
library;

import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;

import 'tracer.dart';

/// The configuration of the OpenTelemetry exporter, read from the
/// environment.
///
/// The variables are the standard ones of the OpenTelemetry specification:
///
/// * `OTEL_SERVICE_NAME` — the name of the service in the backend;
/// * `OTEL_EXPORTER_OTLP_ENDPOINT` — the endpoint of the collector;
/// * `OTEL_SDK_DISABLED` — turns the whole SDK off;
/// * `OTEL_TRACES_SAMPLER_ARG` — the ratio of the traces that are recorded.
class OtelConfig {
  /// Creates a configuration.
  const OtelConfig({
    this.serviceName,
    this.endpoint,
    this.disabled = false,
    this.sampleRatio,
  });

  /// Reads the configuration out of the environment.
  factory OtelConfig.fromEnvironment({Map<String, String>? environment}) {
    final values = environment ?? Platform.environment;
    final ratio = double.tryParse(values['OTEL_TRACES_SAMPLER_ARG'] ?? '');
    return OtelConfig(
      serviceName: values['OTEL_SERVICE_NAME'],
      endpoint: values['OTEL_EXPORTER_OTLP_ENDPOINT'],
      disabled: _isTrue(values['OTEL_SDK_DISABLED']),
      sampleRatio: ratio,
    );
  }

  /// The name of the service, as it appears in the backend.
  final String? serviceName;

  /// The endpoint of the collector.
  final String? endpoint;

  /// Whether the SDK is turned off.
  final bool disabled;

  /// The ratio of the traces that are recorded, between `0` and `1`.
  final double? sampleRatio;

  static bool _isTrue(String? value) =>
      value == 'true' || value == '1' || value == 'TRUE';
}

/// A tracer backed by the OpenTelemetry SDK.
class OtelTracer implements Tracer {
  /// Creates a tracer on top of the SDK [tracer].
  OtelTracer(this._tracer,
      {otel.TextMapPropagator<Map<String, String>, String>? propagator})
      : _propagator = propagator ?? otel.W3CTraceContextPropagator();

  /// Creates a tracer for the service, using the OpenTelemetry SDK.
  ///
  /// The SDK is initialized with the given [config], so the `OTEL_*`
  /// environment variables of the process are honoured.
  static Future<OtelTracer> create({
    String? serviceName,
    OtelConfig? config,
    otel.Sampler? sampler,
  }) async {
    final settings = config ?? OtelConfig.fromEnvironment();
    if (settings.disabled) {
      return OtelTracer(otel.OTel.tracer());
    }

    await otel.OTel.initialize(
      serviceName: serviceName ?? settings.serviceName,
      endpoint: settings.endpoint,
      sampler: sampler ??
          (settings.sampleRatio == null
              ? null
              : otel.TraceIdRatioSampler(settings.sampleRatio!)),
    );
    return OtelTracer(otel.OTel.tracer());
  }

  final otel.Tracer _tracer;
  final otel.TextMapPropagator<Map<String, String>, String> _propagator;

  @override
  Span startSpan(
    String name, {
    SpanContext? parent,
    Map<String, Object?> attributes = const <String, Object?>{},
    SpanKind kind = SpanKind.internal,
  }) {
    final context = _contextOf(parent ?? currentSpan?.context);
    final span = _tracer.startSpan(
      name,
      context: context,
      kind: _kindOf(kind),
      attributes: _attributesOf(attributes),
    );
    return OtelSpan(span);
  }

  @override
  SpanContext? extract(Map<String, String> headers) {
    final context = _propagator.extract(
      otel.OTel.context(),
      headers,
      _MapGetter(headers),
    );
    final spanContext = context.spanContext;
    if (spanContext == null || !spanContext.isValid) {
      return null;
    }
    return SpanContext(
      traceId: spanContext.traceId.hexString,
      spanId: spanContext.spanId.hexString,
      sampled: spanContext.traceFlags.isSampled,
    );
  }

  @override
  void inject(SpanContext context, Map<String, String> headers) {
    final carrier = <String, String>{'traceparent': context.toTraceParent()};
    final otelContext = _propagator.extract(
      otel.OTel.context(),
      carrier,
      _MapGetter(carrier),
    );
    _propagator.inject(otelContext, headers, _MapSetter(headers));
  }

  otel.Context _contextOf(SpanContext? parent) {
    if (parent == null) {
      return otel.OTel.context();
    }
    final carrier = <String, String>{'traceparent': parent.toTraceParent()};
    return _propagator.extract(
      otel.OTel.context(),
      carrier,
      _MapGetter(carrier),
    );
  }

  static otel.SpanKind _kindOf(SpanKind kind) {
    switch (kind) {
      case SpanKind.internal:
        return otel.SpanKind.internal;
      case SpanKind.server:
        return otel.SpanKind.server;
      case SpanKind.client:
        return otel.SpanKind.client;
      case SpanKind.producer:
        return otel.SpanKind.producer;
      case SpanKind.consumer:
        return otel.SpanKind.consumer;
    }
  }

  static otel.Attributes _attributesOf(Map<String, Object?> attributes) {
    if (attributes.isEmpty) {
      return otel.OTel.createAttributes();
    }
    return otel.OTel.attributesFromMap(
      attributes.map(
        (key, value) => MapEntry(key, value ?? ''),
      ),
    );
  }
}

/// A span of the OpenTelemetry SDK.
class OtelSpan implements Span {
  /// Creates a span on top of the SDK [span].
  OtelSpan(this._span);

  final otel.Span _span;

  @override
  SpanContext get context {
    final spanContext = _span.spanContext;
    return SpanContext(
      traceId: spanContext.traceId.hexString,
      spanId: spanContext.spanId.hexString,
      sampled: spanContext.traceFlags.isSampled,
    );
  }

  @override
  void setAttribute(String name, Object? value) {
    switch (value) {
      case null:
        _span.setStringAttribute(name, '');
      case final String text:
        _span.setStringAttribute(name, text);
      case final bool flag:
        _span.setBoolAttribute(name, flag);
      case final int number:
        _span.setIntAttribute(name, number);
      case final double number:
        _span.setDoubleAttribute(name, number);
      default:
        _span.setStringAttribute(name, value.toString());
    }
  }

  @override
  void recordError(Object error, [StackTrace? stackTrace]) {
    _span.recordException(error, stackTrace: stackTrace);
    _span.setStatus(otel.SpanStatusCode.Error, error.toString());
  }

  @override
  void end() => _span.end();
}

class _MapGetter implements otel.TextMapGetter<String> {
  _MapGetter(this._map);

  final Map<String, String> _map;

  @override
  String? get(String key) => _map[key];

  @override
  Iterable<String> keys() => _map.keys;
}

class _MapSetter implements otel.TextMapSetter<String> {
  _MapSetter(this._map);

  final Map<String, String> _map;

  @override
  void set(String key, String value) => _map[key] = value;
}
