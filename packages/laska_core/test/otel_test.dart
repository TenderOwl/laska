import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// A processor that keeps the spans, so a test can assert them.
class _RecordingProcessor extends otel.SpanProcessor {
  final List<otel.Span> spans = <otel.Span>[];

  @override
  Future<void> onStart(otel.Span span, otel.Context? parentContext) async {}

  @override
  Future<void> onEnd(otel.Span span) async {
    spans.add(span);
  }

  @override
  Future<void> onNameUpdate(otel.Span span, String newName) async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<void> forceFlush() async {}
}

void main() {
  late _RecordingProcessor processor;
  late OtelTracer tracer;

  setUpAll(() async {
    processor = _RecordingProcessor();
    await otel.OTel.initialize(
      serviceName: 'laska-test',
      spanProcessor: processor,
      enableMetrics: false,
      enableLogs: false,
    );
    tracer = OtelTracer(otel.OTel.tracer());
  });

  group('OtelConfig', () {
    test('reads the standard environment variables', () {
      final config = OtelConfig.fromEnvironment(
        environment: <String, String>{
          'OTEL_SERVICE_NAME': 'users',
          'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://collector:4318',
          'OTEL_TRACES_SAMPLER_ARG': '0.25',
        },
      );

      expect(config.serviceName, 'users');
      expect(config.endpoint, 'http://collector:4318');
      expect(config.sampleRatio, 0.25);
      expect(config.disabled, isFalse);
    });

    test('reads the off switch', () {
      final config = OtelConfig.fromEnvironment(
        environment: <String, String>{'OTEL_SDK_DISABLED': 'true'},
      );

      expect(config.disabled, isTrue);
    });

    test('has no value for a missing variable', () {
      final config =
          OtelConfig.fromEnvironment(environment: <String, String>{});

      expect(config.serviceName, isNull);
      expect(config.endpoint, isNull);
      expect(config.sampleRatio, isNull);
      expect(config.disabled, isFalse);
    });
  });

  group('OtelTracer', () {
    test('creates a span with a valid context', () {
      final span = tracer.startSpan('test.span');

      expect(span.context.traceId, hasLength(32));
      expect(span.context.spanId, hasLength(16));
      expect(span.context.sampled, isTrue);
    });

    test('exports the span when it ends', () async {
      final before = processor.spans.length;
      final span = tracer.startSpan('test.exported');

      span.end();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(processor.spans.length, greaterThan(before));
      expect(
        processor.spans.map((span) => span.name),
        contains('test.exported'),
      );
    });

    test('keeps the attributes of the span', () async {
      final span = tracer.startSpan(
        'test.attributes',
        attributes: <String, Object?>{'http.request.method': 'GET'},
      );

      span.setAttribute('http.response.status_code', 200);
      span.end();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final exported = processor.spans
          .where((span) => span.name == 'test.attributes')
          .toList();
      expect(exported, isNotEmpty);
      expect(
        exported.last.attributes.getString('http.request.method'),
        'GET',
      );
      expect(
        exported.last.attributes.getInt('http.response.status_code'),
        200,
      );
    });

    test('injects and extracts the trace context', () {
      final span = tracer.startSpan('test.propagation');
      final headers = <String, String>{};

      tracer.inject(span.context, headers);

      expect(headers['traceparent'], isNotNull);
      expect(headers['traceparent'], span.context.toTraceParent());

      final extracted = tracer.extract(headers);

      expect(extracted, isNotNull);
      expect(extracted!.traceId, span.context.traceId);
      expect(extracted.spanId, span.context.spanId);
    });

    test('extracts nothing from a request without a trace', () {
      expect(tracer.extract(<String, String>{}), isNull);
      expect(
          tracer.extract(<String, String>{'traceparent': 'nonsense'}), isNull);
    });

    test('makes a span a child of the trace of the parent', () {
      const parent = SpanContext(
        traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
        spanId: '00f067aa0ba902b7',
      );

      final span = tracer.startSpan('test.child', parent: parent);

      expect(span.context.traceId, parent.traceId);
    });
  });
}
