import 'package:flutter/material.dart';

import '../../brands/brand.dart';
import '../../brands/scanner.dart';
import '../car3d/car_view.dart';
import '../scan_state.dart';
import '../screens/module_screen.dart';
import '../session.dart';
import 'common.dart';

/// The connected car in 3D, with each area coloured by its modules' health.
class CarCard extends StatelessWidget {
  const CarCard({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final identity = session.identity;
    final theme = Theme.of(context);
    return Card(
      child: ListenableBuilder(
        listenable: session.scan,
        builder: (context, _) {
          final scan = session.scan;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(identity.name, style: theme.textTheme.titleLarge),
                          if (identity.year != null)
                            Text(
                              'Model year ${identity.year}',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Paint colour',
                      icon: const Icon(Icons.palette_outlined),
                      onPressed: () => _pickPaint(context, session),
                    ),
                  ],
                ),
              ),
              CarView(
                style: identity.bodyStyle,
                paint: session.carPaint,
                height: 210,
                hotspots: _hotspots(context, session.brand, scan),
                onZoneTap: (zone) => _openZone(context, session, zone),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: _footer(context, session, scan)),
            ],
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context, DiagSession session, ScanState scan) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (scan.scanning) {
      return Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Checking modules ${scan.results.length} of ${scan.total}...', style: muted),
        ],
      );
    }
    if (!scan.hasResults) {
      return Row(
        children: [
          Expanded(child: Text('Scan the modules to see the health of each area.', style: muted)),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: () => scan.start(session.transport, session.brand), child: const Text('Scan')),
        ],
      );
    }
    return Text('Drag to turn the car. Tap an area to see its modules.', style: muted);
  }

  static Map<CarZone, Hotspot> _hotspots(BuildContext context, Brand brand, ScanState scan) {
    final grey = Theme.of(context).colorScheme.outline;
    final out = <CarZone, Hotspot>{};
    for (final zone in CarZone.values) {
      final defs = brand.modules.where((m) => m.zone == zone).toList();
      if (defs.isEmpty) continue;
      final results = [for (final d in defs) ?scan.find(d.txId)];
      final present = results.where((r) => r.present);
      final faults = present.fold(0, (n, r) => n + (r.dtcs?.length ?? 0));
      if (results.length < defs.length || present.isEmpty) {
        out[zone] = Hotspot(color: grey, label: zone.short);
      } else if (faults > 0) {
        out[zone] = Hotspot(color: toneColor(context, Tone.bad), label: '${zone.short} · $faults');
      } else {
        out[zone] = Hotspot(color: toneColor(context, Tone.ok), label: zone.short, icon: Icons.check_rounded);
      }
    }
    return out;
  }

  Future<void> _openZone(BuildContext context, DiagSession session, CarZone zone) async {
    final def = await showModalBottomSheet<ModuleDef>(
      context: context,
      builder: (_) => _ZoneSheet(zone: zone),
    );
    if (def == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ModuleScreen(module: def)));
    if (!session.connected) return;
    try {
      await session.scan.refresh(session.transport, session.brand, def);
    } catch (_) {
      // The card keeps the previous status; a rescan fixes it.
    }
  }

  Future<void> _pickPaint(BuildContext context, DiagSession session) => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paint colour', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final c in carPaints)
                  GestureDetector(
                    onTap: () {
                      session.setCarPaint(c);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == session.carPaint
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: c == session.carPaint ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// The modules in one area of the car and their status.
class _ZoneSheet extends StatelessWidget {
  const _ZoneSheet({required this.zone});
  final CarZone zone;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final theme = Theme.of(context);
    final defs = session.brand.modules.where((m) => m.zone == zone);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(zone.label, style: theme.textTheme.titleLarge),
          ),
          for (final def in defs) _row(context, def, session.scan.find(def.txId)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ModuleDef def, ModuleInfo? info) {
    final dtcs = info?.dtcs;
    final Widget status;
    if (info == null) {
      status = Pill('not scanned', color: Theme.of(context).colorScheme.outline);
    } else if (!info.present) {
      status = Pill('not found', color: Theme.of(context).colorScheme.outline);
    } else if (dtcs == null) {
      status = Pill('?', color: Theme.of(context).colorScheme.outline);
    } else if (dtcs.isEmpty) {
      status = Pill('OK', color: toneColor(context, Tone.ok), icon: Icons.check_rounded);
    } else {
      status = Pill('${dtcs.length} fault${dtcs.length == 1 ? '' : 's'}', color: toneColor(context, Tone.bad));
    }
    final enabled = info == null || info.present;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      enabled: enabled,
      leading: ModuleBadge(def.address.isEmpty ? def.name[0] : def.address, dimmed: !enabled),
      title: Text(def.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: info?.partNumber.isNotEmpty == true ? Text(info!.partNumber) : null,
      trailing: status,
      onTap: enabled ? () => Navigator.pop(context, def) : null,
    );
  }
}
