import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'controller.dart';
import '../core/widgets/dashboard_widgets.dart';
import '../features/home/home_page.dart';
import '../features/network_analyzer/network_page.dart';
import '../features/smart_file_manager/files_page.dart';
import '../features/device_doctor/device_page.dart';
import '../features/settings/settings_page.dart';
import '../features/reports/reports_page.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomePage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/network', builder: (_, _) => const NetworkPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/files', builder: (_, _) => const FilesPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/device', builder: (_, _) => const DevicePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);

class AzUtilityApp extends ConsumerWidget {
  const AzUtilityApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(controllerProvider);
    final light = app.settings['light'] == true;
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(
        seedColor: app.settings['purple'] == true
            ? const Color(0xff895eff)
            : cyan,
        brightness: brightness,
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: dark
            ? const Color(0xff091425)
            : const Color(0xffedf3fa),
        visualDensity: app.settings['compact'] == true
            ? VisualDensity.compact
            : VisualDensity.standard,
        cardTheme: CardThemeData(
          color: dark ? const Color(0xff172b45) : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: cyan.withValues(alpha: 0.12)),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: dark ? const Color(0xff101e33) : Colors.white,
        ),
        navigationRailTheme: NavigationRailThemeData(
          backgroundColor: dark ? const Color(0xff101e33) : Colors.white,
        ),
      );
    }

    return MaterialApp.router(
      title: 'AZ Utility',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: app.settings['reducedMotion'] == true),
        child: child!,
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool expanded = true;
  static const labels = [
    'Home',
    'Network Analyzer',
    'Smart File Manager',
    'Device Doctor',
    'Reports',
    'Settings',
  ];
  static const icons = [
    Icons.dashboard_rounded,
    Icons.network_check_rounded,
    Icons.folder_rounded,
    Icons.monitor_heart_rounded,
    Icons.assessment_rounded,
    Icons.settings_rounded,
  ];
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(controllerProvider);
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    void go(int index) => widget.shell.goBranch(index);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            go(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            go(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            go(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            go(3),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                CircleAvatar(
                  child: Text(
                    'AZ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AZ Utility',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (desktop)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(Platform.operatingSystem),
                ),
              IconButton(
                tooltip: 'Switch theme',
                icon: const Icon(Icons.brightness_6),
                onPressed: () =>
                    app.set('light', app.settings['light'] != true),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => go(5),
              ),
            ],
          ),
          body: Row(
            children: [
              if (desktop)
                NavigationRail(
                  extended: expanded,
                  selectedIndex: widget.shell.currentIndex,
                  onDestinationSelected: go,
                  leading: IconButton(
                    tooltip: 'Expand or collapse sidebar',
                    onPressed: () => setState(() => expanded = !expanded),
                    icon: const Icon(Icons.menu),
                  ),
                  destinations: [
                    for (int i = 0; i < labels.length; i++)
                      NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(labels[i]),
                      ),
                  ],
                ),
              Expanded(
                child: Column(
                  children: [
                    if (app.busy || app.error != null)
                      Material(
                        color: app.error != null
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(app.error ?? app.status),
                                  ),
                                  if (app.busy)
                                    TextButton(
                                      onPressed: app.cancel,
                                      child: const Text('Cancel'),
                                    ),
                                ],
                              ),
                              if (app.busy)
                                LinearProgressIndicator(value: app.progress),
                            ],
                          ),
                        ),
                      ),
                    Expanded(child: widget.shell),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: widget.shell.currentIndex == 4
                      ? 0
                      : widget.shell.currentIndex == 5
                      ? 4
                      : widget.shell.currentIndex,
                  onDestinationSelected: (i) => go(i == 4 ? 5 : i),
                  destinations: [
                    for (final i in [0, 1, 2, 3, 5])
                      NavigationDestination(
                        icon: Icon(icons[i]),
                        label: [
                          'Home',
                          'Network',
                          'Files',
                          'Device',
                          'Reports',
                          'Settings',
                        ][i],
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
