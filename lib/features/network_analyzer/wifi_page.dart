import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/controller.dart';
import '../../core/widgets/dashboard_widgets.dart';

class WifiPage extends ConsumerWidget {
  const WifiPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    final metrics = app.metrics
        .where(
          (m) => RegExp(
            r'Wi-Fi|network|adapter|Local IP|DNS|Internet',
            caseSensitive: false,
          ).hasMatch(m.label),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi & network interfaces')),
      body: PageBody(
        title: 'Connection details',
        subtitle:
            'Current connection only. No background Wi-Fi scans or scan-throttle bypass.',
        children: [
          MetricGrid(metrics: metrics),
          if (metrics.isEmpty)
            const Panel(
              child: Text(
                'No network information available from this adapter.',
              ),
            ),
          const Panel(
            child: Text(
              'Link speed describes the local radio connection, not internet throughput. Signal measurements and private identifiers may be withheld by the operating system. Windows may require Location access for WLAN identifiers. Android requires precise Location permission and Location services for SSID/BSSID.',
            ),
          ),
          ActionWrap(
            children: [
              OutlinedButton(
                onPressed: app.refreshMetrics,
                child: const Text('Refresh'),
              ),
              if (Platform.isAndroid)
                FilledButton(
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Show Wi-Fi identifiers?'),
                        content: const Text(
                          'Android protects SSID and BSSID with precise Location permission. AZ Utility uses it only to read the current Wi-Fi connection, without storing location or scanning nearby networks. Enable Location services if identifiers remain redacted.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Continue'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await app.run('Wi-Fi permission', (token) async {
                        final response = await app.native.invoke(
                          'requestWifiPermission',
                        );
                        app.result = {'permission': response};
                      });
                    }
                  },
                  child: const Text('Allow Wi-Fi identifiers'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
