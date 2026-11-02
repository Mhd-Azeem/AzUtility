/// Numeric observations retain their unit-bearing field names. Missing values
/// are absent, never coerced to zero for a comparison.
Map<String, double> numericObservations(dynamic payload) {
  final output = <String, double>{};
  void visit(dynamic value, String prefix) {
    if (value is num && value.isFinite) {
      output[prefix] = value.toDouble();
    } else if (value is Map) {
      for (final e in value.entries) {
        if (e.key != 'progress' && e.key != 'checksum') {
          visit(e.value, prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}');
        }
      }
    }
  }

  visit(payload, '');
  if (payload is Map && payload['samples'] is List) {
    final samples = (payload['samples'] as List).whereType<Map>().toList();
    final tcp = samples.map((s) => s['tcpMs']).whereType<num>().toList();
    if (tcp.isNotEmpty) {
      output['mean TCP (ms)'] =
          tcp.fold<double>(0, (n, t) => n + t) / tcp.length;
      if (tcp.length > 1) {
        double total = 0;
        for (int i = 1; i < tcp.length; i++) {
          total += (tcp[i] - tcp[i - 1]).abs();
        }
        output['successive jitter (ms)'] = total / (tcp.length - 1);
      }
    }
    if (samples.isNotEmpty) {
      output['DNS/TCP failure (%)'] =
          100 * (samples.length - tcp.length) / samples.length;
    }
  }
  return output;
}

List<double?> recordTimeline(dynamic payload) =>
    payload is Map && payload['samples'] is List
    ? (payload['samples'] as List)
          .whereType<Map>()
          .map((s) => (s['tcpMs'] as num?)?.toDouble())
          .toList()
    : [];

String observationText(double? value) =>
    value == null ? 'Not measured' : value.toStringAsFixed(3);
