import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/database/app_database.dart';
import '../core/models.dart';
import '../core/platform/native_bridge.dart';
import '../features/network_analyzer/network_service.dart';
import '../features/smart_file_manager/file_service.dart';
import '../features/device_doctor/device_service.dart';

final databaseProvider = Provider<AppDatabase>(
  (_) => throw StateError('Database not initialized'),
);
final controllerProvider = ChangeNotifierProvider<AppController>(
  (ref) => AppController(ref.watch(databaseProvider)),
);

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController(this.db) {
    WidgetsBinding.instance.addObserver(this);
    ready = _initialize();
  }
  final AppDatabase db;
  late final Future<void> ready;
  final native = const NativeBridge();
  final network = NetworkService();
  final files = FileService();
  late final device = DeviceService(native);
  Map<String, dynamic> settings = {};
  List<Metric> metrics = [];
  List<Map<String, dynamic>> history = [];
  final samples = ListQueue<NetworkSample>();
  final metricHistory = <String, ListQueue<double>>{};
  List<List<IndexedFile>> duplicateGroups = [];
  String? root;
  String? error;
  String status = 'Ready';
  double? progress;
  Map<String, Object?> result = {};
  Cancellation? _cancel;
  bool get busy => _cancel != null;
  Timer? _monitor;
  bool _disposed = false;
  bool _refreshing = false;
  Future<void> _initialize() async {
    try {
      settings = await db.settings();
      files.index.addAll(await db.loadIndex());
      root = settings['scanRoot'] as String?;
      await refresh();
    } catch (e) {
      error = 'Local storage could not be loaded: $e';
      await refreshMetrics();
    }
    _startMonitor();
  }

  void _startMonitor() {
    if (_disposed) return;
    _monitor?.cancel();
    _monitor = Timer.periodic(
      Duration(
        seconds: ((settings['refreshSeconds'] as num?)?.toInt() ?? 5).clamp(
          2,
          60,
        ),
      ),
      (_) => refreshMetrics(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startMonitor();
      refreshMetrics();
    } else {
      _monitor?.cancel();
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> refreshMetrics() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      metrics = await device.snapshot();
      for (final metric in metrics.where((m) => m.ratio != null)) {
        final values = metricHistory.putIfAbsent(
          metric.label,
          ListQueue<double>.new,
        );
        values.add(metric.ratio! * 100);
        if (values.length > 180) values.removeFirst();
      }
    } catch (e) {
      error = 'Monitoring: $e';
    } finally {
      _refreshing = false;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      history = await db.history();
    } catch (e) {
      error = 'Local history is unavailable: $e';
    }
    await refreshMetrics();
    notifyListeners();
  }

  Future<void> set(String key, dynamic value) async {
    final previous = settings[key];
    settings[key] = value;
    notifyListeners();
    try {
      await db.set(key, value);
      if (key == 'refreshSeconds') _startMonitor();
    } catch (e) {
      settings[key] = previous;
      error = 'Preference could not be saved: $e';
      notifyListeners();
    }
  }

  void cancel() {
    _cancel?.cancel();
    status = 'Cancelling…';
    notifyListeners();
  }

  Future<void> run(
    String title,
    Future<void> Function(Cancellation) operation,
  ) async {
    if (busy) return;
    final token = Cancellation();
    _cancel = token;
    error = null;
    status = title;
    progress = null;
    result = {};
    notifyListeners();
    try {
      await operation(token);
      token.check();
      status = '$title completed';
    } on Cancelled {
      status = '$title cancelled';
    } catch (e) {
      if (token.cancelled) {
        status = '$title cancelled';
      } else {
        error = e.toString();
        status = '$title failed';
      }
    } finally {
      _cancel = null;
      progress = null;
      await refresh();
    }
  }

  Future<void> testNetwork({int count = 10}) => run('Connection diagnostics', (
    token,
  ) async {
    final uri = network.endpoint(
      settings['endpoint'] as String? ?? 'https://example.com',
    );
    final session = <Map<String, Object?>>[];
    try {
      for (int i = 0; i < count; i++) {
        token.check();
        final sample = await network.measure(uri, token);
        samples.add(sample);
        if (samples.length > 900) samples.removeFirst();
        session.add(sample.toJson());
        progress = (i + 1) / count;
        status = 'Sample ${i + 1}/$count · ${sample.error ?? 'Connected'}';
        notifyListeners();
        if (i < count - 1) {
          await Future<void>.delayed(
            Duration(
              milliseconds:
                  ((settings['sampleSeconds'] as num?)?.toInt() ?? 1) * 1000,
            ),
          );
        }
      }
    } finally {
      if (session.isNotEmpty) {
        await db.save('network', 'TCP / HTTPS diagnostics', {
          'endpoint': uri.toString(),
          'samples': session,
          'cancelled': token.cancelled,
        });
      }
    }
  });
  Future<void> speedTest(bool upload) => run(
    upload ? 'Upload test' : 'Download test',
    (token) async {
      final configured =
          settings[upload ? 'uploadEndpoint' : 'downloadEndpoint'] as String? ??
          '';
      if (configured.isEmpty) {
        throw StateError(
          'Configure your own compatible HTTPS transfer endpoint in Settings.',
        );
      }
      await for (final update in network.throughput(
        network.endpoint(configured),
        upload: upload,
        limit: ((settings['transferMiB'] as num?)?.toInt() ?? 8) * 1024 * 1024,
        cancel: token,
      )) {
        final seconds = (update['seconds'] as num).toDouble();
        result = {
          ...update,
          if (seconds > 0) 'Mbps': (update['bytes'] as num) * 8 / seconds / 1e6,
          if (seconds > 0) 'MB/s': (update['bytes'] as num) / seconds / 1e6,
        };
        progress =
            (update['bytes'] as int) /
            (((settings['transferMiB'] as num?)?.toInt() ?? 8) * 1024 * 1024);
        notifyListeners();
      }
      await db.save(
        'network',
        upload ? 'Upload throughput' : 'Download throughput',
        result,
      );
    },
  );
  Future<void> scan() => run('Storage scan', (token) async {
    if (root == null) throw StateError('Choose an accessible folder first.');
    await set('scanRoot', root);
    await for (final update in files.scan(
      root!,
      token,
      exclusions: (settings['exclusions'] as String? ?? '.git,node_modules')
          .split(','),
    )) {
      status =
          '${update.files} files · ${bytes(update.total)} · ${update.errors} skipped/errors';
      result = {
        'files': update.files,
        'bytes': update.total,
        'errors': update.errors,
        'root': root,
        'coverage': 'Selected accessible folder only; bounded to 100,000 files',
      };
      notifyListeners();
    }
    await db.saveIndex(files.index);
    await db.save('files', 'Storage scan', result);
  });
  Future<void> findDuplicates() => run('Duplicate scan', (token) async {
    duplicateGroups = await files.duplicates(token, (done, total) {
      progress = done / total;
      notifyListeners();
    });
    await db.save('files', 'Duplicate scan', {
      'groups': duplicateGroups.length,
      'copies': duplicateGroups.fold<int>(0, (n, g) => n + g.length - 1),
      'method':
          'Size groups and full SHA-256; size and modification time rechecked',
    });
  });
  Future<void> benchmark(String kind) => run('$kind benchmark', (token) async {
    await for (final update in device.benchmark(kind, token)) {
      result = update;
      progress = (update['progress'] as num?)?.toDouble();
      notifyListeners();
    }
    await db.save('device', '$kind benchmark', result);
  });
  Future<void> inventory() => run('Device diagnostics', (token) async {
    token.check();
    await refreshMetrics();
    await db.save(
      'device',
      'Hardware inventory',
      metrics
          .map(
            (m) => {
              'label': m.label,
              'value': m.value,
              'status': m.status.name,
            },
          )
          .toList(),
    );
  });
  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _monitor?.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}
