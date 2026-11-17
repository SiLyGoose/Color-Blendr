import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../state/ads_controller.dart';
import '../state/auth_controller.dart';
import '../state/generator_controller.dart';
import 'generator/generator_page.dart';
import 'library/library_page.dart';
import 'settings/settings_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  /// Renewals, cancellations and refunds happen outside the app, so re-check
  /// the plan whenever it comes back to the foreground.
  late final _lifecycle = AppLifecycleListener(
    onResume: () => ref.read(authProvider.notifier).refreshProfile(),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // Start listening.
    // Free accounts: ask for ad consent where needed and load the first ad,
    // so it's ready by the fifth generate. Pro never loads the ad SDK.
    ref.listenManual(authProvider, (_, auth) {
      if (auth.hasValue) ref.read(adsControllerProvider.notifier).prepare();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _select(int tab) => setState(() => _tab = tab);

  void _openInGenerator(SavedPalette palette) {
    ref.read(generatorProvider.notifier).open(palette);
    _select(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keep each tab alive so scroll position and in-progress work survive switching.
      body: IndexedStack(
        index: _tab,
        children: [
          const GeneratorPage(),
          LibraryPage(onCreate: () => _select(0), onOpen: _openInGenerator),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.palette_outlined),
            selectedIcon: Icon(Icons.palette),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
