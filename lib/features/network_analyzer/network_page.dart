import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/controller.dart';
import '../../core/models.dart';
import '../../core/widgets/dashboard_widgets.dart';
import 'network_service.dart';

class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});
  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  int range = 60;
  List<Map<String, Object?>> hosts = [];
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(controllerProvider);
    final cutoff = DateTime.now().subtract(Duration(seconds: range));
    final samples = app.samples.where((s) => s.time.isAfter(cutoff)).toList();
    final stats = NetworkStats(samples);
    String ms(double? value) =>
        value == null ? 'Not measured' : '${value.toStringAsFixed(1)} ms';
    return PageBody(
      title: 'Network Analyzer',
      subtitle: 'DNS, TCP and HTTPS measurements · No ICMP ping is used',
      children: [
        MetricGrid(
          metrics: [
            Metric('TCP connection latency', ms(stats.mean)),
            Metric('Successive-sample jitter', ms(stats.jitter)),
            Metric(
              'TCP failure estimate',
              stats.failurePercent == null
                  ? 'Not measured'
                  : '${stats.failurePercent!.toStringAsFixed(1)}%',
            ),
            Metric(
              'Last HTTPS header latency',
              ms(samples.lastOrNull?.httpsMs),
            ),
            Metric(
              'Resolved addresses',
              samples.lastOrNull?.addresses.join(', ') ?? 'Not measured',
            ),
            Metric(
              'Latest observation',
              samples.lastOrNull?.error ??
                  (samples.isEmpty ? 'Not measured' : 'Connection succeeded'),
            ),
          ],
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'TCP response timeline',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  DropdownButton<int>(
                    value: range,
                    items: [
                      for (final value in [30, 60, 300, 900])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            value < 60
                                ? '30 seconds'
                                : '${value ~/ 60} minute${value == 60 ? '' : 's'}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => range = v!),
                  ),
                ],
              ),
              LatencyChart(values: samples.map((s) => s.tcpMs).toList()),
              const Text(
                'Jitter = mean absolute difference of successive successful TCP samples. Failure estimate = failed TCP attempts / total attempts; this is not ICMP packet loss.',
              ),
            ],
          ),
        ),
        ActionWrap(
          children: [
            FilledButton.icon(
              onPressed: app.busy ? null : () => app.testNetwork(count: range),
              icon: const Icon(Icons.play_arrow),
              label: Text('Start $range samples'),
            ),
            OutlinedButton(
              onPressed: app.busy ? null : () => app.testNetwork(count: 1),
              child: const Text('Single diagnostic'),
            ),
            OutlinedButton(
              onPressed: app.busy ? null : () => app.speedTest(false),
              child: const Text('Test download'),
            ),
            OutlinedButton(
              onPressed: app.busy ? null : () => app.speedTest(true),
              child: const Text('Test upload'),
            ),
            OutlinedButton(
              onPressed: app.busy ? null : _lan,
              child: const Text('Discover private LAN'),
            ),
          ],
        ),
        if (app.result.isNotEmpty)
          Panel(
            child: SelectableText(
              app.result.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            ),
          ),
        if ((app.settings['downloadEndpoint'] as String? ?? '').isEmpty)
          const Panel(
            child: Text(
              'Speed test setup required: configure an HTTPS download URL and optional POST upload URL you are authorized to use. The transfer limit is enforced locally; mobile data may be consumed.',
            ),
          ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Troubleshooting evidence',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (samples.isEmpty)
                const Text('Not assessed. Run a diagnostic session.'),
              if (samples.any((s) => s.error != null))
                const Text(
                  'Attention recommended: one or more attempts failed. Check the recorded error, configured endpoint, local connection and DNS settings. This alone does not identify an ISP fault.',
                ),
              if ((stats.mean ?? 0) > 300)
                const Text(
                  'Attention recommended: average TCP connection time exceeds 300 ms for this endpoint. Distance, routing and congestion may contribute; compare another endpoint. Confidence: limited.',
                ),
              if ((stats.jitter ?? 0) > 50)
                const Text(
                  'Attention recommended: successive TCP times vary by more than 50 ms on average. Repeat on another connection. Confidence: limited.',
                ),
              if (samples.isNotEmpty &&
                  samples.every((s) => s.error == null) &&
                  (stats.mean ?? 0) <= 300)
                const Text(
                  'Good: the sampled endpoint responded without recorded errors. Other services and Wi-Fi signal quality are not assessed.',
                ),
            ],
          ),
        ),
        if (hosts.isNotEmpty)
          Panel(
            child: Column(
              children: [
                const Text(
                  'Hosts accepting TCP port 443 (other devices may be missed)',
                ),
                for (final host in hosts)
                  ListTile(
                    title: Text('${host['ip']}'),
                    trailing: Text(
                      '${(host['ms'] as num).toStringAsFixed(1)} ms',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _lan() async {
    final addresses = (await localAddresses()).where(privateV4).toList();
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Scan an authorized local network'),
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'This probes TCP port 443 on up to 254 addresses in the selected private /24. Only continue on a network you are authorized to inspect.',
            ),
          ),
          if (addresses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No assigned private IPv4 interface is available.'),
            ),
          for (final ip in addresses)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ip),
              child: Text('Scan $ip /24'),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final app = ref.read(controllerProvider);
    hosts = [];
    await app.run('LAN discovery', (token) async {
      await for (final host in app.network.scanLan(selected, token)) {
        app.progress = (host['progress'] as num).toDouble();
        if (host.containsKey('ip')) hosts.add(host);
        app.notifyListeners();
      }
      await app.db.save('network', 'Private LAN discovery', {
        'interface': selected,
        'hosts': hosts,
        'method':
            'TCP 443 /24; closed ports are not evidence of absent devices',
      });
    });
  }
}
