import 'dart:io';

enum CapabilityStatus { available, permissionRequired, unsupported, temporarilyUnavailable, error }

class Metric {
  const Metric(this.label, this.value, {this.status = CapabilityStatus.available, this.ratio});
  final String label;
  final String value;
  final CapabilityStatus status;
  final double? ratio;
  factory Metric.fromMap(Map<dynamic, dynamic> map) => Metric(
    map['label'] as String, map['value']?.toString() ?? 'Unavailable',
    status: CapabilityStatus.values.firstWhere((s) => s.name == map['status'], orElse: () => CapabilityStatus.available),
    ratio: (map['ratio'] as num?)?.toDouble(),
  );
}

class Cancellation {
  bool cancelled = false;
  final List<void Function()> _callbacks = [];
  void onCancel(void Function() callback) { if (cancelled) { callback(); } else { _callbacks.add(callback); } }
  void cancel() { cancelled = true; for (final callback in _callbacks) { callback(); } _callbacks.clear(); }
  void check() { if (cancelled) throw const Cancelled(); }
}
class Cancelled implements Exception { const Cancelled(); @override String toString() => 'Operation cancelled'; }

String bytes(num value) {
  if (value < 1024) return '${value.toInt()} B';
  const units = ['KiB', 'MiB', 'GiB', 'TiB'];
  double amount = value / 1024; int index = 0;
  while (amount >= 1024 && index < units.length - 1) { amount /= 1024; index++; }
  return '${amount.toStringAsFixed(1)} ${units[index]}';
}

class IndexedFile {
  const IndexedFile(this.path, this.size, this.modified, this.category);
  final String path;
  final int size;
  final DateTime modified;
  final String category;
  Map<String, Object?> toJson() => {'path':path, 'size':size, 'modified':modified.toIso8601String(), 'category':category};
  factory IndexedFile.fromJson(Map<String, dynamic> j) => IndexedFile(j['path'] as String, j['size'] as int, DateTime.parse(j['modified'] as String), j['category'] as String);
}

String classify(String path) {
  final extension = path.split('.').last.toLowerCase();
  const groups = {
    'Images': ['jpg','jpeg','png','gif','webp','bmp','heic','svg'],
    'Videos': ['mp4','mkv','avi','mov','webm','m4v'],
    'Audio': ['mp3','wav','flac','aac','ogg','m4a'],
    'Documents': ['pdf','doc','docx','txt','odt','rtf','xls','xlsx','csv','ppt','pptx'],
    'Archives': ['zip','7z','rar','tar','gz','bz2'],
  };
  for (final entry in groups.entries) { if (entry.value.contains(extension)) return entry.key; }
  return 'Other';
}

bool privateV4(String value) {
  final octets = value.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.any((n) => n == null || n < 0 || n > 255)) return false;
  return octets[0] == 10 || (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31) || (octets[0] == 192 && octets[1] == 168);
}

Future<List<String>> localAddresses() async => [for (final i in await NetworkInterface.list()) for (final a in i.addresses) a.address];
