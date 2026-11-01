import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/controller.dart';
import '../../core/widgets/dashboard_widgets.dart';

class DevicePage extends ConsumerWidget {
  const DevicePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    return PageBody(
      title: 'Device Doctor',
      subtitle:
          'Live native observations · Refreshes every five seconds · No arbitrary health score',
      children: [
        MetricGrid(metrics: app.metrics),
        if (app.metricHistory.isNotEmpty)
          Panel(
            child: DefaultTabController(
              length: app.metricHistory.length,
              child: Column(
                children: [
                  TabBar(
                    isScrollable: true,
                    tabs: app.metricHistory.keys
                        .map((label) => Tab(text: label))
                        .toList(),
                  ),
                  SizedBox(
                    height: 220,
                    child: TabBarView(
                      children: app.metricHistory.values
                          .map(
                            (values) => Padding(
                              padding: const EdgeInsets.all(12),
                              child: LatencyChart(values: values.toList()),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Text(
                    'Percent history · ${app.settings['refreshSeconds'] ?? 5} second samples · Last 180 samples in memory',
                  ),
                ],
              ),
            ),
          ),
        ActionWrap(
          children: [
            FilledButton.icon(
              onPressed: app.busy ? null : app.inventory,
              icon: const Icon(Icons.fact_check),
              label: const Text('Save diagnostic inventory'),
            ),
            for (final kind in ['CPU', 'Memory', 'Storage'])
              OutlinedButton(
                onPressed: app.busy ? null : () => app.benchmark(kind),
                child: Text('$kind benchmark'),
              ),
          ],
        ),
        if (app.result.isNotEmpty)
          Panel(
            child: SelectableText(
              app.result.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            ),
          ),
        const Panel(
          child: Text(
            'Benchmarks are bounded: CPU runs 20 arithmetic chunks; memory uses 8 MiB chunks (64 MiB total); storage writes a 16 MiB temporary file and removes it afterward. Storage results include OS caching effects. Cancel is checked between chunks.',
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Interactive tests',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ActionWrap(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DisplayTest(),
                      ),
                    ),
                    icon: const Icon(Icons.display_settings),
                    label: const Text('Screen colors & touch'),
                  ),
                  for (final entry in [
                    ('speaker', 'Speaker tone'),
                    ('microphone', 'Microphone record & playback'),
                    ('vibrate', 'Vibration'),
                    ('sensors', 'Sensor inventory'),
                  ])
                    OutlinedButton(
                      onPressed: app.busy
                          ? null
                          : () => nativeTest(context, ref, entry.$1, entry.$2),
                      child: Text(entry.$2),
                    ),
                  OutlinedButton(
                    onPressed: app.busy
                        ? null
                        : () => app.testNetwork(count: 1),
                    child: const Text('Connectivity'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Evidence-based observations',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final metric in app.metrics.where(
                (m) =>
                    m.ratio != null &&
                    (m.label.contains('used') || m.label.contains('CPU load')),
              ))
                ListTile(
                  leading: Icon(
                    (metric.ratio ?? 0) > 0.9
                        ? Icons.warning_amber
                        : Icons.check_circle_outline,
                  ),
                  title: Text(
                    '${metric.label}: ${metric.ratio! > 0.9 ? 'Attention recommended' : 'Observed'}',
                  ),
                  subtitle: Text(
                    '${metric.value}. ${metric.ratio! > 0.9 ? 'Usage exceeds 90%; review running apps or storage.' : 'This observation alone does not assess hardware health.'}',
                  ),
                ),
              const Text(
                'Not assessed: component lifespan, battery wear percentage and hidden hardware faults. Manual tests require your own observation.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> nativeTest(
    BuildContext context,
    WidgetRef ref,
    String method,
    String title,
  ) async {
    if (method == 'microphone') {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Record microphone for 3 seconds?'),
          content: const Text(
            'Microphone access is used only for this test. A temporary local recording is played back and deleted; nothing is uploaded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record & play'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    final app = ref.read(controllerProvider);
    await app.run(title, (token) async {
      final value = await app.native.invoke(method);
      token.check();
      app.result = {'result': value?.toString() ?? 'Unavailable'};
      await app.db.save('device', title, app.result);
    });
  }
}

class DisplayTest extends StatefulWidget {
  const DisplayTest({super.key});
  @override
  State<DisplayTest> createState() => _DisplayTestState();
}

class _DisplayTestState extends State<DisplayTest> {
  int color = 0;
  final points = <Offset>[];
  @override
  Widget build(BuildContext context) {
    const colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.white,
      Colors.black,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen & touch test'),
        actions: [
          TextButton(
            onPressed: () =>
                setState(() => color = (color + 1) % colors.length),
            child: const Text('Next color'),
          ),
          TextButton(
            onPressed: () => setState(points.clear),
            child: const Text('Clear'),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => setState(() {
          points.add(details.localPosition);
          if (points.length > 500) points.removeAt(0);
        }),
        onTapDown: (details) => setState(() {
          points.add(details.localPosition);
          if (points.length > 500) points.removeAt(0);
        }),
        child: CustomPaint(
          painter: _TouchPainter(colors[color], points.toList()),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TouchPainter extends CustomPainter {
  _TouchPainter(this.color, this.points);
  final Color color;
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(color, BlendMode.src);
    final pen = Paint()..color = Colors.cyan;
    for (final point in points) {
      canvas.drawCircle(point, 7, pen);
    }
  }

  @override
  bool shouldRepaint(_TouchPainter old) => true;
}
