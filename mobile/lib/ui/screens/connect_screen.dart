import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../platform/ble_channel.dart';
import '../session.dart';
import '../widgets/common.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  Object? _error;
  final _host = TextEditingController(text: '192.168.0.10');
  final _port = TextEditingController(text: '35000');

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
    if (device != null) await _run(() => session.connectChannel(() => BleByteChannel.connect(device)));
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.directions_car_filled, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Car Diagnostics', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Plug an ELM327 adapter into the OBD port under the dashboard, turn the ignition on, then connect.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (session.busy)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(session.status.isEmpty ? 'Connecting...' : session.status),
                    ],
                  ),
                ),
              )
            else ...[
              if (_error != null) ErrorPanel(error: _error!),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: const Text('Bluetooth adapter'),
                  subtitle: const Text('Bluetooth LE (4.0+) ELM327 adapters'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickBluetooth,
                ),
              ),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.wifi),
                  title: const Text('Wi-Fi adapter'),
                  subtitle: const Text("Join the adapter's Wi-Fi network first"),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => _run(
                          () => session.connectWifi(_host.text.trim(), int.tryParse(_port.text.trim()) ?? 35000),
                        ),
                        child: const Text('Connect'),
                      ),
                    ),
                  ],
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Demo car'),
                  subtitle: const Text('Simulated VW Golf. Try everything without a car.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _run(session.connectDemo),
                  onLongPress: () => _run(() => session.connectDemo(throughEmulatedAdapter: true)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            ListTile(
              title: const Text('Choose your adapter'),
              subtitle: const Text('Searching for Bluetooth LE devices...'),
              trailing: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
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
                    ListTile(
                      leading: Icon(looksLikeObdAdapter(d) ? Icons.settings_input_component : Icons.bluetooth),
                      title: Text(d.name),
                      subtitle: Text('Signal ${d.rssi} dBm'),
                      onTap: () => Navigator.pop(context, d),
                    ),
                  if (shown.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No adapters found yet. Make sure the adapter is plugged in and the ignition is on. '
                        'Classic Bluetooth adapters (that pair in the system settings) are not supported.',
                        textAlign: TextAlign.center,
                      ),
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
}
