import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/controller.dart';
import '../../core/widgets/dashboard_widgets.dart';
import '../../core/models.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    final overview = app.metrics
        .where(
          (metric) =>
              metric.label == 'System CPU load' ||
              metric.label == 'System RAM used' ||
              metric.label.contains('volume used') ||
              metric.label == 'Battery charge',
        )
        .take(5)
        .toList();
    final last = app.samples.lastOrNull;
    final connection =
        app.metrics
            .where((metric) => metric.label == 'Active network')
            .firstOrNull
            ?.value ??
        (last == null ? 'Not tested' : last.error ?? 'Endpoint responded');
    final storage = app.files.index.fold<int>(
      0,
      (total, file) => total + file.size,
    );
    return PageBody(
      title: 'Your system. In focus.',
      subtitle:
          '${DateTime.now().toLocal().toString().substring(0, 16)} · ${Platform.operatingSystem} · Private by design',
      children: [
        if (app.metrics.isEmpty) const DashboardSkeleton(),
        MetricGrid(metrics: [Metric('Connection', connection), ...overview]),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in [
                (
                  Icons.network_check,
                  'AZ Network Analyzer',
                  '$connection\nTCP: ${last?.tcpMs?.toStringAsFixed(1) ?? 'Not measured'}${last?.tcpMs == null ? '' : ' ms'}',
                  '/network',
                ),
                (
                  Icons.folder,
                  'AZ Smart File Manager',
                  '${app.files.index.length} indexed files · ${bytes(storage)}\nExplore accessible folders safely.',
                  '/files',
                ),
                (
                  Icons.monitor_heart,
                  'AZ Device Doctor',
                  '${Platform.numberOfProcessors} logical processors\nInspect live hardware and run diagnostics.',
                  '/device',
                ),
              ])
                SizedBox(
                  width: c.maxWidth > 820 ? (c.maxWidth - 24) / 3 : c.maxWidth,
                  child: Panel(
                    onTap: () => context.go(item.$4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.$1, color: cyan, size: 36),
                        const SizedBox(height: 24),
                        Text(
                          item.$2,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(item.$3),
                        const SizedBox(height: 16),
                        const Row(
                          children: [
                            Text('Open utility'),
                            Spacer(),
                            Icon(Icons.arrow_forward_rounded, color: cyan),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        ActionWrap(
          children: [
            FilledButton.icon(
              onPressed: app.busy ? null : () => app.testNetwork(count: 3),
              icon: const Icon(Icons.bolt),
              label: const Text('Test connection'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/files'),
              icon: const Icon(Icons.manage_search),
              label: const Text('Scan storage'),
            ),
            OutlinedButton.icon(
              onPressed: app.busy ? null : app.inventory,
              icon: const Icon(Icons.fact_check),
              label: const Text('Run diagnostics'),
            ),
            TextButton(
              onPressed: () => context.go('/reports'),
              child: const Text('View reports'),
            ),
          ],
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (app.history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Your completed scans and diagnostic sessions will appear here.',
                  ),
                ),
              for (final record in app.history.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text('${record['title']}'),
                  subtitle: Text('${record['created']}'),
                  onTap: () => context.go('/reports'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
