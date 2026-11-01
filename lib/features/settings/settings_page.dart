import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/controller.dart';
import '../../core/widgets/dashboard_widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    Widget toggle(String title, String key, {bool fallback = false}) =>
        SwitchListTile(
          title: Text(title),
          value: app.settings[key] as bool? ?? fallback,
          onChanged: (v) => app.set(key, v),
        );
    Widget input(String title, String key, String fallback) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        key: ValueKey('$key-${app.settings[key]}'),
        initialValue: app.settings[key]?.toString() ?? fallback,
        decoration: InputDecoration(
          labelText: title,
          border: const OutlineInputBorder(),
        ),
        onFieldSubmitted: (v) => app.set(key, v.trim()),
      ),
    );
    return PageBody(
      title: 'Settings',
      subtitle:
          'Preferences and diagnostic records stay on this device. Submit text fields to save.',
      children: [
        Panel(
          child: Column(
            children: [
              toggle('Light theme', 'light'),
              toggle('Purple accent', 'purple'),
              toggle('Reduced motion', 'reducedMotion'),
              toggle('Compact display density', 'compact'),
              toggle('Image thumbnails', 'thumbnails', fallback: true),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device monitoring',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    ListTile(
                      title: const Text('Refresh interval'),
                      trailing: DropdownButton<int>(
                        value:
                            (app.settings['refreshSeconds'] as num?)?.toInt() ??
                            5,
                        items: [
                          for (final seconds in [2, 5, 10, 30, 60])
                            DropdownMenuItem(
                              value: seconds,
                              child: Text('$seconds seconds'),
                            ),
                        ],
                        onChanged: (value) => app.set('refreshSeconds', value),
                      ),
                    ),
                    const Text(
                      'Benchmarks use conservative fixed limits. Monitoring stops while the app is in the background.',
                    ),
                    ExpansionTile(
                      title: const Text('Permission and capability status'),
                      children: app.metrics
                          .map(
                            (metric) => ListTile(
                              title: Text(metric.label),
                              subtitle: Text(metric.status.name),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
              Text('Network', style: Theme.of(context).textTheme.titleLarge),
              input(
                'Diagnostic HTTPS endpoint',
                'endpoint',
                'https://example.com',
              ),
              input(
                'Download test endpoint (owned/authorized)',
                'downloadEndpoint',
                '',
              ),
              input(
                'Upload POST endpoint (owned/authorized)',
                'uploadEndpoint',
                '',
              ),
              const Text(
                'The upload test sends generated zero bytes only. User files are never uploaded.',
              ),
              ListTile(
                title: const Text('Transfer cap'),
                trailing: DropdownButton<int>(
                  value: (app.settings['transferMiB'] as num?)?.toInt() ?? 8,
                  items: [
                    for (final n in [1, 8, 16, 32, 64])
                      DropdownMenuItem(value: n, child: Text('$n MiB')),
                  ],
                  onChanged: (v) => app.set('transferMiB', v),
                ),
              ),
              ListTile(
                title: const Text('Sample interval'),
                trailing: DropdownButton<int>(
                  value: (app.settings['sampleSeconds'] as num?)?.toInt() ?? 1,
                  items: [
                    for (final n in [1, 2, 5, 10])
                      DropdownMenuItem(value: n, child: Text('$n seconds')),
                  ],
                  onChanged: (v) => app.set('sampleSeconds', v),
                ),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Files & privacy',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              input(
                'Excluded folder names (comma-separated)',
                'exclusions',
                '.git,node_modules',
              ),
              const Text(
                'History is bounded to 500 records per category. The latest scan index stores file paths, sizes, modification dates and categories locally. Clearing file history also removes this index. Native permission prompts appear only when requested.',
              ),
              for (final category in ['network', 'files', 'device'])
                ListTile(
                  title: Text('Clear $category history'),
                  trailing: const Icon(Icons.delete_outline),
                  onTap: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Clear $category history?'),
                        content: const Text(
                          'This removes local diagnostic records only.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await app.db.clear(category);
                      if (category == 'files') {
                        app.files.index.clear();
                        app.duplicateGroups.clear();
                      }
                      await app.refresh();
                    }
                  },
                ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AZ Utility 1.0.0 (1)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Platform: ${Platform.operatingSystem}\nApplication: com.az.utility\nRepository: https://github.com/Mhd-Azeem/AzUtility',
              ),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'AZ Utility',
                  applicationVersion: '1.0.0',
                ),
                child: const Text('Open-source licenses'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
