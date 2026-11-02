import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/platform/native_bridge.dart';

class SensorPage extends StatefulWidget {
  const SensorPage({super.key});
  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> with WidgetsBindingObserver {
  final native = const NativeBridge();
  Timer? timer;
  List<dynamic> rows = [];
  String status = 'Starting supported sensors…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  Future<void> start() async {
    try {
      final supported = await native.invoke('startSensors');
      if (!mounted) {
        await native.invoke('stopSensors');
        return;
      }
      setState(
        () => status = supported is List
            ? (supported.isEmpty
                  ? 'Unsupported: no supported sensors reported'
                  : 'Move the device to inspect live readings. Acceleration m/s²; angular velocity rad/s; magnetic field μT; light lux; proximity cm. Accuracy is Android sensor accuracy (0–3), not a diagnostic score.')
            : '$supported',
      );
      if (supported is! List || supported.isEmpty) return;
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          final value = await native.invoke('sensorReadings');
          if (mounted && value is List) setState(() => rows = value);
        } catch (e) {
          timer?.cancel();
          if (mounted) setState(() => status = '$e');
        }
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Sensor adapter unavailable: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    timer?.cancel();
    unawaited(native.invoke('stopSensors'));
    if (state == AppLifecycleState.resumed) start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    unawaited(native.invoke('stopSensors'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Live sensors')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(status),
        for (final dynamic row in rows)
          Card(
            child: ListTile(
              title: Text('${row['name']}'),
              subtitle: Text(
                '${row['type']}\n${row['values']}\nAccuracy: ${row['accuracy']} · sample timestamp ${row['timestampNanos']} ns',
              ),
            ),
          ),
      ],
    ),
  );
}
