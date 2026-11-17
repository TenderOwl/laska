import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('TestTracer', () {
    test('records the spans', () {
      final tracer = TestTracer();

      final span = tracer.startSpan('test.span', attributes: <String, Object?>{
        'key': 'value',
      });
      span.end();

      expect(tracer.spans, hasLength(1));
      expect(tracer.lastSpan.name, 'test.span');
      expect(tracer.lastSpan.attributes['key'], 'value');
      expect(tracer.lastSpan.ended, isTrue);
    });

    test('keeps the spans of the same name apart', () {
      final tracer = TestTracer();

      tracer.startSpan('a');
      tracer.startSpan('b');
      tracer.startSpan('a');

      expect(tracer.spansNamed('a'), hasLength(2));
      expect(tracer.spansNamed('b'), hasLength(1));
    });

    test('lists the spans that are still open', () {
      final tracer = TestTracer();

      final span = tracer.startSpan('a');
      tracer.startSpan('b');
      span.end();

      expect(tracer.openSpans, hasLength(1));
      expect(tracer.openSpans.single.name, 'b');
    });

    test('injects and extracts the trace context', () {
      final tracer = TestTracer();
      final span = tracer.startSpan('a');
      final headers = <String, String>{};

      tracer.inject(span.context, headers);

      expect(headers['traceparent'], span.context.toTraceParent());
      expect(tracer.extract(headers)!.traceId, span.context.traceId);
    });

    test('makes a span a child of the current span', () async {
      final tracer = TestTracer();

      await runWithSpan(tracer.startSpan('parent'), () async {
        tracer.startSpan('child');
      });

      final child = tracer.spansNamed('child').single;
      expect(child.parent, isNotNull);
      expect(child.parent!.traceId, tracer.spans.first.context.traceId);
    });
  });
}
