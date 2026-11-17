import 'package:laska_core/laska_core.dart';

/// A tracer that records the spans instead of exporting them.
///
/// The fake lets a test assert what the service traced: which spans were
/// created, which attributes they carry and which trace they belong to.
class TestTracer implements Tracer {
  /// Creates a tracer that records the spans.
  TestTracer({this.name = 'test'});

  /// The name of the tracer.
  final String name;

  /// The spans that were started, in the order they were started.
  final List<TestSpan> spans = <TestSpan>[];

  /// The spans that are still open.
  List<TestSpan> get openSpans => spans.where((span) => !span.ended).toList();

  /// The spans called [spanName].
  List<TestSpan> spansNamed(String spanName) =>
      spans.where((span) => span.name == spanName).toList();

  /// The last span that was started.
  TestSpan get lastSpan => spans.last;

  @override
  Span startSpan(
    String spanName, {
    SpanContext? parent,
    Map<String, Object?> attributes = const <String, Object?>{},
    SpanKind kind = SpanKind.internal,
  }) {
    final span = TestSpan(
      name: spanName,
      parent: parent ?? currentSpan?.context,
      kind: kind,
      attributes: Map<String, Object?>.of(attributes),
    );
    spans.add(span);
    return span;
  }

  @override
  SpanContext? extract(Map<String, String> headers) {
    final value =
        headers['traceparent'] ?? headers['traceparent'.toLowerCase()];
    return SpanContext.parseTraceParent(value);
  }

  @override
  void inject(SpanContext context, Map<String, String> headers) {
    headers['traceparent'] = context.toTraceParent();
  }
}

/// A span recorded by a [TestTracer].
class TestSpan implements Span {
  /// Creates a span.
  TestSpan({
    required this.name,
    required this.parent,
    required this.kind,
    required this.attributes,
    this.traceId,
  });

  /// The name of the span.
  final String name;

  /// The context of the parent of the span, if any.
  final SpanContext? parent;

  /// The kind of the span.
  final SpanKind kind;

  /// The attributes of the span.
  final Map<String, Object?> attributes;

  /// The id of the trace the span belongs to.
  final String? traceId;

  /// The errors that were recorded on the span.
  final List<Object> errors = <Object>[];

  /// Whether the span was ended.
  bool ended = false;

  late final SpanContext _context = SpanContext(
    traceId: traceId ?? parent?.traceId ?? _randomId(32),
    spanId: _randomId(16),
  );

  @override
  SpanContext get context => _context;

  @override
  void setAttribute(String name, Object? value) {
    attributes[name] = value;
  }

  @override
  void recordError(Object error, [StackTrace? stackTrace]) {
    errors.add(error);
  }

  @override
  void end() {
    ended = true;
  }

  static String _randomId(int length) {
    final random = DateTime.now().microsecondsSinceEpoch;
    var value = random.toRadixString(16).padLeft(length, '0');
    if (value.length > length) {
      value = value.substring(value.length - length);
    }
    return value.padRight(length, '0');
  }
}
