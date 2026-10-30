import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/obd/obd_client.dart';
import '../../core/obd/pids.dart';
import '../../core/obd/readiness.dart';
import '../session.dart';
import '../../core/service_log.dart';
import '../widgets/car_card.dart';
import '../widgets/skeleton.dart';
import 'battery_screen.dart';
import 'history_screen.dart';
import 'performance_screen.dart';
import 'service_screen.dart';
import 'trip_screen.dart';
import 'readiness_screen.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class _Overview {
  _Overview(this.status, this.voltage, this.coolant, this.distanceSinceClear, this.supported, this.readiness);
  final MonitorStatus? status;
  final Reading? voltage;
  final Reading? coolant;
  final Reading? distanceSinceClear;
  final Map<int, Set<int>> supported;
  final Readiness? readiness;
}

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key, required this.onNavigate});

  final void Function(int tab) onNavigate;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  Future<_Overview>? _future;

  void Function(int tab) get onNavigate => widget.onNavigate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load(SessionScope.read(context));
  }

  void _reload() => setState(() => _future = _load(SessionScope.read(context)));

  Future<_Overview> _load(DiagSession session) async {
    final obd = session.obd;
    Future<Reading?> optional(String pid) async {
      try {
        return await obd.read(pid);
      } on CarDiagException {
        return null;
      }
    }

    MonitorStatus? status;
    try {
      status = await obd.monitorStatus();
    } on NoResponseException {
      status = null;
    }
    return _Overview(
      status,
      await optional('module_voltage'),
      await optional('coolant_temp'),
      await optional('distance_since_clear'),
      await obd.supportedPids(),
      await _readiness(obd),
    );
  }

  static Future<Readiness?> _readiness(ObdClient obd) async {
    try {
      return await obd.readiness();
    } on CarDiagException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<_Overview>(
        future: _future,
        builder: (context, snap) {
          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              const CarCard(),
              if (snap.connectionState != ConnectionState.done)
                const Skeleton(tiles: true, cards: 2)
              else if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorPanel(error: snap.error!, onRetry: _reload),
                )
              else
                ..._details(context, session, snap.data!),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _details(BuildContext context, DiagSession session, _Overview o) {
    final mil = o.status?.milOn ?? false;
    final codes = o.status?.dtcCount ?? 0;
    final volts = o.voltage?.numeric;
    return [
      StatusBanner(
        tone: mil ? Tone.bad : (codes > 0 ? Tone.warn : Tone.ok),
        icon: mil ? Icons.warning_rounded : Icons.verified_rounded,
        title: mil ? 'Check engine light on' : 'Engine looks healthy',
        subtitle: o.status == null
            ? 'The engine did not report its status'
            : codes == 0
            ? 'No emissions fault codes stored'
            : '$codes emissions fault code${codes == 1 ? '' : 's'} stored',
        action: codes > 0
            ? IconButton.filledTonal(
                tooltip: 'Show fault codes',
                onPressed: () => onNavigate(HomeTabs.faults),
                icon: const Icon(Icons.arrow_forward_rounded),
              )
            : null,
      ),
      if (o.readiness case final r?) _ReadinessCard(readiness: r),
      const _ServiceCard(),
      const SizedBox(height: 6),
      TileGrid(
        children: [
          StatTile(
            icon: Icons.battery_charging_full_rounded,
            label: 'Battery voltage',
            value: volts == null ? '–' : '${volts.toStringAsFixed(1)} V',
            tone: volts == null
                ? Tone.neutral
                : volts < 12.0
                ? Tone.bad
                : volts < 12.4
                ? Tone.warn
                : Tone.ok,
          ),
          StatTile(
            icon: Icons.thermostat_rounded,
            label: 'Coolant temperature',
            value: o.coolant == null ? '–' : session.settings.format(o.coolant!.pid, o.coolant!.value),
            tone: (o.coolant?.numeric ?? 0) > 110 ? Tone.bad : Tone.neutral,
          ),
          StatTile(
            icon: Icons.route_rounded,
            label: 'Since codes cleared',
            value: o.distanceSinceClear == null
                ? '–'
                : session.settings.format(o.distanceSinceClear!.pid, o.distanceSinceClear!.value),
          ),
          StatTile(icon: Icons.memory_rounded, label: 'Engine computers', value: '${o.supported.length}'),
        ],
      ),
      const SectionHeader('Vehicle'),
      Card(
        child: Column(
          children: [
            InfoRow('VIN', session.vin ?? 'Not reported', selectable: true),
            const Divider(height: 1, indent: 16, endIndent: 16),
            InfoRow('Make', session.brand.name),
            const Divider(height: 1, indent: 16, endIndent: 16),
            InfoRow('Adapter', session.adapterDescription),
            for (final e in o.supported.entries) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              InfoRow(obdEcuName(e.key), '${e.value.where(pidsByNumber.containsKey).length} sensors'),
            ],
          ],
        ),
      ),
      const SectionHeader('Go to'),
      TileGrid(
        children: [
          _Shortcut(icon: Icons.speed_rounded, label: 'Live data', onTap: () => onNavigate(HomeTabs.live)),
          _Shortcut(
            icon: Icons.developer_board_rounded,
            label: 'Scan modules',
            onTap: () => onNavigate(HomeTabs.modules),
          ),
          if (session.brand.codingDid != null)
            _Shortcut(icon: Icons.tune_rounded, label: 'Coding', onTap: () => onNavigate(HomeTabs.coding)),
          _Shortcut(icon: Icons.report_problem_rounded, label: 'Fault codes', onTap: () => onNavigate(HomeTabs.faults)),
          _Shortcut(
            icon: Icons.history_rounded,
            label: 'Scan history',
            onTap: () => _open(context, const HistoryScreen()),
          ),
        ],
      ),
      const SectionHeader('Tools'),
      TileGrid(
        children: [
          _Shortcut(
            icon: Icons.local_gas_station_rounded,
            label: 'Trip computer',
            onTap: () => _open(context, const TripScreen()),
          ),
          _Shortcut(
            icon: Icons.battery_charging_full_rounded,
            label: 'Battery test',
            onTap: () => _open(context, const BatteryScreen()),
          ),
          _Shortcut(
            icon: Icons.timer_outlined,
            label: 'Performance',
            onTap: () => _open(context, const PerformanceScreen()),
          ),
          _Shortcut(
            icon: Icons.build_circle_outlined,
            label: 'Service log',
            onTap: () => _open(context, ServiceScreen(vin: session.vin ?? '', carName: session.identity.title)),
          ),
        ],
      ),
    ];
  }
}

void _open(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

/// The most urgent service reminder, if the owner keeps a service log.
class _ServiceCard extends StatefulWidget {
  const _ServiceCard();

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  ServiceLog? _log;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final session = SessionScope.read(context);
    try {
      final log = await session.loadServiceLog(session.vin ?? '');
      if (mounted) setState(() => _log = log);
    } catch (_) {
      // No service log is fine.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final log = _log;
    final now = DateTime.now();
    final next = log?.reminders(now).firstOrNull;
    if (log == null || next == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: TintedIcon(Icons.build_circle_rounded, color: toneColor(context, dueTone(next.status)), size: 40),
        title: Text(next.type.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(describeReminder(next, log, session.settings, now)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ServiceScreen(vin: session.vin ?? '', carName: session.identity.title),
            ),
          );
          if (mounted) _load();
        },
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            TintedIcon(icon, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness});
  final Readiness readiness;

  @override
  Widget build(BuildContext context) {
    final (tone, icon, title, _) = describeVerdict(readiness);
    final done = readiness.monitors.where((m) => m.complete).length;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: TintedIcon(icon, color: toneColor(context, tone), size: 40),
        title: Text('Inspection: $title', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$done of ${readiness.monitors.length} emissions self-tests complete'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ReadinessScreen())),
      ),
    );
  }
}
