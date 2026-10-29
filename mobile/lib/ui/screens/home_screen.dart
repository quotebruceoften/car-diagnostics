import 'package:flutter/material.dart';

import '../../brands/registry.dart';
import '../session.dart';
import 'coding_tab.dart';
import 'faults_tab.dart';
import 'live_tab.dart';
import 'modules_tab.dart';
import 'overview_tab.dart';

/// Tab indexes, so tabs can send the user to each other.
abstract final class HomeTabs {
  static const overview = 0;
  static const faults = 1;
  static const live = 2;
  static const modules = 3;
  static const coding = 4;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = HomeTabs.overview;

  void _go(int tab) => setState(() => _tab = tab);

  Future<void> _chooseBrand(DiagSession session) async {
    final picked = await showModalBottomSheet<Brand>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Car make', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final b in [...supportedBrands, genericBrand])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: Icon(
                  b.id == session.brand.id ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(b.name),
                onTap: () => Navigator.pop(context, b),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await session.setBrand(picked);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final theme = Theme.of(context);
    final tabs = [
      OverviewTab(onNavigate: _go),
      const FaultsTab(),
      LiveTab(active: _tab == HomeTabs.live),
      const ModulesTab(),
      CodingTab(onNavigate: _go),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.brand.name),
            if (session.vin != null)
              Text(
                session.vin!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Change car make',
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () => _chooseBrand(session),
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.power_settings_new_rounded),
            onPressed: session.disconnect,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.report_problem_outlined),
            selectedIcon: Icon(Icons.report_problem_rounded),
            label: 'Faults',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed_rounded),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.developer_board_outlined),
            selectedIcon: Icon(Icons.developer_board_rounded),
            label: 'Modules',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Coding',
          ),
        ],
      ),
    );
  }
}
