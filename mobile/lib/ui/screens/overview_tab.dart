import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/obd/obd_client.dart';
import '../../core/obd/pids.dart';
import '../session.dart';
import '../widgets/common.dart';

class _Overview {
  _Overview(this.status, this.voltage, this.supported, this.distanceSinceClear);
  final MonitorStatus? status;
  final Reading? voltage;
  final Map<int, Set<int>> supported;
  final Reading? distanceSinceClear;
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

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
      await obd.supportedPids(),
      await optional('distance_since_clear'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return AsyncLoader<_Overview>(
      load: () => _load(session),
      builder: (context, o, reload) {
        final theme = Theme.of(context);
        final mil = o.status?.milOn ?? false;
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: mil ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Icon(mil ? Icons.warning_amber : Icons.check_circle_outline, size: 36),
                  title: Text(
                    mil ? 'Check engine light is ON' : 'Check engine light is off',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    o.status == null ? 'Status not reported' : '${o.status!.dtcCount} emissions fault code(s) stored',
                  ),
                ),
              ),
              const SectionHeader('Vehicle'),
              _row('VIN', session.vin ?? 'Not reported'),
              _row('Make', session.brand.name),
              _row('Adapter', session.adapterDescription),
              if (o.voltage != null) _row('Battery / module voltage', '${o.voltage}'),
              if (o.distanceSinceClear != null) _row('Distance since codes cleared', '${o.distanceSinceClear}'),
              const SectionHeader('Engine computers (OBD-II)'),
              for (final e in o.supported.entries)
                _row(obdEcuName(e.key), '${e.value.where(pidsByNumber.containsKey).length} readable sensors'),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) => ListTile(
    dense: true,
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
    ),
  );
}
