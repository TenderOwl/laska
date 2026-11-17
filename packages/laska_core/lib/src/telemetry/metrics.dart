/// The metrics of the service.
///
/// The runtime records the metrics of the requests it handles; a service
/// records its own with the same [Meter]. The metrics are exposed in the
/// Prometheus text format, so any Prometheus compatible scraper can read them.
library;

/// A counter that only goes up.
abstract class Counter {
  /// Adds [value] to the counter.
  void add(int value, [Map<String, String> labels = const <String, String>{}]);
}

/// A histogram of values.
abstract class Histogram {
  /// Records [value] in the histogram.
  void record(
    double value, [
    Map<String, String> labels = const <String, String>{},
  ]);
}

/// Creates the instruments of the service.
abstract class Meter {
  /// Returns the counter called [name].
  ///
  /// The instrument is created once: asking for the same name twice returns
  /// the same counter.
  Counter counter(String name, {String? description, String? unit});

  /// Returns the histogram called [name].
  Histogram histogram(
    String name, {
    String? description,
    String? unit,
    List<double>? buckets,
  });
}

/// The default buckets of a histogram, in seconds.
const List<double> defaultHistogramBuckets = <double>[
  0.005,
  0.01,
  0.025,
  0.05,
  0.1,
  0.25,
  0.5,
  1,
  2.5,
  5,
  10,
];

/// The metrics of a service, held in memory.
///
/// The registry is the [Meter] of the runtime. It is also the source of the
/// `/metrics` endpoint.
class MetricsRegistry implements Meter {
  /// Creates an empty registry.
  MetricsRegistry();

  final Map<String, _Family> _families = <String, _Family>{};

  @override
  Counter counter(String name, {String? description, String? unit}) {
    final family = _families.putIfAbsent(
      name,
      () => _Family(
        name: name,
        type: 'counter',
        description: description,
        unit: unit,
      ),
    );
    return _RegistryCounter(family);
  }

  @override
  Histogram histogram(
    String name, {
    String? description,
    String? unit,
    List<double>? buckets,
  }) {
    final family = _families.putIfAbsent(
      name,
      () => _Family(
        name: name,
        type: 'histogram',
        description: description,
        unit: unit,
        buckets: buckets ?? defaultHistogramBuckets,
      ),
    );
    return _RegistryHistogram(family);
  }

  /// The metrics in the Prometheus text exposition format.
  String toPrometheus() => prometheusText(this);
}

/// The metrics of [registry] in the Prometheus text exposition format.
///
/// The format is the one of the Prometheus exposition format 0.0.4, so a
/// scraper reads the output without any conversion.
String prometheusText(MetricsRegistry registry) {
  final buffer = StringBuffer();
  for (final family in registry._families.values) {
    if (family.description != null) {
      buffer.writeln('# HELP ${family.name} ${family.description}');
    }
    buffer.writeln('# TYPE ${family.name} ${family.type}');
    for (final series in family.series.values) {
      if (family.type == 'histogram') {
        _writeHistogramSeries(buffer, family, series);
      } else {
        buffer.writeln(
          '${family.name}${_labels(series.labels)} '
          '${_number(series.value)}',
        );
      }
    }
  }
  return buffer.toString();
}

void _writeHistogramSeries(
  StringBuffer buffer,
  _Family family,
  _Series series,
) {
  var cumulative = 0;
  for (var index = 0; index < family.buckets.length; index++) {
    cumulative += series.counts[index];
    final labels = <String, String>{
      ...series.labels,
      'le': _number(family.buckets[index]),
    };
    buffer.writeln(
      '${family.name}_bucket${_labels(labels)} $cumulative',
    );
  }
  final labels = <String, String>{...series.labels, 'le': '+Inf'};
  buffer.writeln(
    '${family.name}_bucket${_labels(labels)} '
    '${series.counts.fold<int>(0, (sum, value) => sum + value)}',
  );
  buffer.writeln('${family.name}_sum${_labels(series.labels)} '
      '${_number(series.sum)}');
  buffer.writeln(
    '${family.name}_count${_labels(series.labels)} ${series.count}',
  );
}

/// Renders the labels of a metric series.
String _labels(Map<String, String> labels) {
  if (labels.isEmpty) {
    return '';
  }
  final parts = labels.entries
      .map((entry) => '${entry.key}="${_escape(entry.value)}"')
      .join(',');
  return '{$parts}';
}

/// Escapes the value of a label.
String _escape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n');

/// Renders a number the way Prometheus expects it.
String _number(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

class _Family {
  _Family({
    required this.name,
    required this.type,
    this.description,
    this.unit,
    this.buckets = const <double>[],
  });

  final String name;
  final String type;
  final String? description;
  final String? unit;
  final List<double> buckets;
  final Map<String, _Series> series = <String, _Series>{};

  _Series _seriesFor(Map<String, String> labels) {
    final key = labels.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .toList()
        .join(',');
    return series.putIfAbsent(
      key,
      () => _Series(labels, buckets: buckets.length),
    );
  }
}

class _Series {
  _Series(this.labels, {required int buckets})
      : counts = List<int>.filled(buckets, 0);

  final Map<String, String> labels;
  final List<int> counts;
  double value = 0;
  double sum = 0;
  int count = 0;

  void add(int delta) {
    value += delta;
  }

  void observe(double observation, List<double> buckets) {
    sum += observation;
    count++;
    for (var index = 0; index < buckets.length; index++) {
      if (observation <= buckets[index]) {
        counts[index]++;
        return;
      }
    }
    // The observation is above every bucket, so it only counts in the `+Inf`
    // bucket of the exposition.
  }
}

class _RegistryCounter implements Counter {
  _RegistryCounter(this._family);

  final _Family _family;

  @override
  void add(int value, [Map<String, String> labels = const <String, String>{}]) {
    _family._seriesFor(labels).add(value);
  }
}

class _RegistryHistogram implements Histogram {
  _RegistryHistogram(this._family);

  final _Family _family;

  @override
  void record(
    double value, [
    Map<String, String> labels = const <String, String>{},
  ]) {
    _family._seriesFor(labels).observe(value, _family.buckets);
  }
}
