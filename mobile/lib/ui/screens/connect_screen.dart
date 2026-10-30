import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../platform/ble_channel.dart';
import '../session.dart';
import '../settings.dart';
import 'service_screen.dart';
import 'settings_screen.dart';
import '../widgets/common.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  Object? _error;
  bool _wifiOpen = false;
  final _host = TextEditingController(text: '192.168.0.10');
  final _port = TextEditingController(text: '35000');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = SessionScope.read(context);
    final saved = session.settings.lastAdapter;
    // Reconnect to the last adapter once per app launch.
    if (!session.autoReconnectTried && session.settings.autoReconnect && saved != null) {
      session.autoReconnectTried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !session.connected && !session.busy) _reconnect(saved);
      });
    }
  }

  Future<void> _reconnect(SavedAdapter a) {
    final session = SessionScope.read(context);
    return _run(
      () => a.isBle
          ? session.connectChannel(() => BleByteChannel.connectTo(a.id!, a.name), remember: a)
          : session.connectWifi(a.host!, a.port!),
    );
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() connect) async {
    setState(() => _error = null);
    try {
      await connect();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pickBluetooth() async {
    final session = SessionScope.read(context);
    final device = await showModalBottomSheet<DiscoveredDevice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BleScanSheet(),
    );
    if (device == null) return;
    await _run(
      () => session.connectChannel(
        () => BleByteChannel.connect(device),
        remember: SavedAdapter.ble(id: device.id, name: device.name.isEmpty ? 'Bluetooth adapter' : device.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Header(scheme: scheme, theme: theme),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
            sliver: SliverList.list(
              children: session.busy
                  ? [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: LoadingView(message: session.status.isEmpty ? 'Connecting...' : session.status),
                        ),
                      ),
                    ]
                  : [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: ErrorPanel(error: _error!),
                        ),
                      if (session.settings.lastAdapter case final saved?) ...[
                        const SectionHeader('Your adapter'),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                TintedIcon(saved.isBle ? Icons.bluetooth_connected_rounded : Icons.wifi_rounded),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(saved.name, style: theme.textTheme.titleMedium),
                                      Text(saved.detail, style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                ),
                                FilledButton(onPressed: () => _reconnect(saved), child: const Text('Connect')),
                              ],
                            ),
                          ),
                        ),
                      ],
                      SectionHeader(session.settings.lastAdapter == null ? 'Connect' : 'Other ways to connect'),
                      _OptionCard(
                        icon: Icons.bluetooth_rounded,
                        title: 'Bluetooth adapter',
                        subtitle: 'Bluetooth LE (4.0+) ELM327 adapters',
                        onTap: _pickBluetooth,
                      ),
                      _OptionCard(
                        icon: Icons.wifi_rounded,
                        title: 'Wi-Fi adapter',
                        subtitle: "Join the adapter's Wi-Fi network first",
                        trailing: Icon(_wifiOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                        onTap: () => setState(() => _wifiOpen = !_wifiOpen),
                        expanded: _wifiOpen
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: TextField(
                                            controller: _host,
                                            decoration: const InputDecoration(labelText: 'Address'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            controller: _port,
                                            decoration: const InputDecoration(labelText: 'Port'),
                                            keyboardType: TextInputType.number,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: () => _run(
                                          () => session.connectWifi(
                                            _host.text.trim(),
                                            int.tryParse(_port.text.trim()) ?? 35000,
                                          ),
                                        ),
                                        child: const Text('Connect'),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
                      ),
                      _OptionCard(
                        icon: Icons.science_rounded,
                        title: 'Demo car',
                        subtitle: 'A simulated VW Golf. Try every feature without a car.',
                        onTap: () => _run(session.connectDemo),
                        onLongPress: () => _run(() => session.connectDemo(throughEmulatedAdapter: true)),
                      ),
                      if (session.settings.lastCar case final car?) ...[
                        const SectionHeader('Without the adapter'),
                        _OptionCard(
                          icon: Icons.build_circle_outlined,
                          title: 'Service log',
                          subtitle: '${car.name}: services and reminders',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ServiceScreen(vin: car.vin, carName: car.name),
                            ),
                          ),
                        ),
                      ],
                      const SectionHeader('Good to know'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const TintedIcon(Icons.lightbulb_outline_rounded, size: 36),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Works with standard ELM327 adapters such as the Vgate iCar Pro BLE or vLinker. '
                                  "Adapters locked to one maker's app (like Carly) won't connect.\n\n"
                                  'Plug the adapter into the OBD port under the dashboard and turn the ignition on.',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.scheme, required this.theme});
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [scheme.primary, Color.lerp(scheme.primary, const Color(0xFF0B1B33), 0.55)!],
      ),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.directions_car_filled_rounded, size: 36, color: scheme.onPrimary),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Settings',
                  color: scheme.onPrimary,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Car Diagnostics', style: theme.textTheme.headlineMedium?.copyWith(color: scheme.onPrimary)),
            const SizedBox(height: 6),
            Text(
              'Fault codes, live data and module coding.',
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.expanded,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? expanded;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TintedIcon(icon),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                trailing ?? const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
        ?expanded,
      ],
    ),
  );
}

class _BleScanSheet extends StatefulWidget {
  const _BleScanSheet();

  @override
  State<_BleScanSheet> createState() => _BleScanSheetState();
}

class _BleScanSheetState extends State<_BleScanSheet> {
  final _devices = <String, DiscoveredDevice>{};
  StreamSubscription<DiscoveredDevice>? _scan;
  Object? _error;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _scan = BleByteChannel.scan().listen(
      (d) => setState(() => _devices[d.id] = d),
      onError: (Object e) => setState(() => _error = e),
    );
  }

  @override
  void dispose() {
    _scan?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final named = _devices.values.where((d) => d.name.isNotEmpty);
    final likely = named.where(looksLikeObdAdapter).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    final others = named.where((d) => !looksLikeObdAdapter(d)).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    final shown = [...likely, if (_showAll) ...others];
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Choose your adapter', style: theme.textTheme.titleLarge)),
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorPanel(error: _error!),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final d in shown)
                    Card(
                      child: ListTile(
                        leading: TintedIcon(
                          looksLikeObdAdapter(d) ? Icons.settings_input_component_rounded : Icons.bluetooth_rounded,
                          size: 40,
                        ),
                        title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_signal(d.rssi)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(context, d),
                      ),
                    ),
                  if (shown.isEmpty && _error == null)
                    const EmptyState(
                      icon: Icons.bluetooth_searching_rounded,
                      title: 'Searching...',
                      message:
                          'Make sure the adapter is plugged in and the ignition is on. '
                          'Adapters that pair in the system Bluetooth settings (classic Bluetooth) are not supported.',
                    ),
                  if (others.isNotEmpty)
                    SwitchListTile(
                      title: Text('Show all devices (${others.length} more)'),
                      value: _showAll,
                      onChanged: (v) => setState(() => _showAll = v),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _signal(int rssi) => rssi > -60
      ? 'Strong signal'
      : rssi > -80
      ? 'Good signal'
      : 'Weak signal';
}
