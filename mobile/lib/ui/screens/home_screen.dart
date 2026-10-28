import 'package:flutter/material.dart';

import '../../brands/registry.dart';
import '../session.dart';
import 'faults_tab.dart';
import 'live_tab.dart';
import 'modules_tab.dart';
import 'overview_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  Future<void> _chooseBrand(DiagSession session) async {
    final picked = await showDialog<Brand>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Car make'),
        children: [
          for (final b in [...supportedBrands, genericBrand])
            ListTile(
              leading: Icon(b.id == session.brand.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(b.name),
              onTap: () => Navigator.pop(context, b),
            ),
        ],
      ),
    );
    if (picked != null) await session.setBrand(picked);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final tabs = [const OverviewTab(), const FaultsTab(), LiveTab(active: _tab == 2), const ModulesTab()];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.brand.name),
            if (session.vin != null) Text(session.vin!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Change car make',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => _chooseBrand(session),
          ),
          IconButton(tooltip: 'Disconnect', icon: const Icon(Icons.link_off), onPressed: session.disconnect),
        ],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning_amber),
            label: 'Faults',
          ),
          NavigationDestination(icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'Live data'),
          NavigationDestination(
            icon: Icon(Icons.developer_board_outlined),
            selectedIcon: Icon(Icons.developer_board),
            label: 'Modules',
          ),
        ],
      ),
    );
  }
}
