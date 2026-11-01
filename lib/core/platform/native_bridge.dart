import 'package:flutter/services.dart';
import '../models.dart';

class NativeBridge {
  const NativeBridge();
  static const channel = MethodChannel('com.az.utility/native');
  Future<List<Metric>> snapshot() async {
    try {
      final result = await channel.invokeListMethod<dynamic>('snapshot');
      return (result ?? []).map((m) => Metric.fromMap(m as Map)).toList();
    } on MissingPluginException {
      return [const Metric('Native monitoring', 'Adapter unavailable', status: CapabilityStatus.unsupported)];
    }
  }
  Future<String?> chooseTree() => channel.invokeMethod<String>('chooseTree');
  Future<dynamic> invoke(String name, [Map<String, dynamic>? arguments]) => channel.invokeMethod<dynamic>(name, arguments);
}
