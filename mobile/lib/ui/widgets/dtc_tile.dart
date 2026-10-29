import 'package:flutter/material.dart';

import '../../core/obd/dtc.dart';
import 'common.dart';

/// One fault code: code badge, description and status.
class DtcTile extends StatelessWidget {
  const DtcTile({super.key, required this.dtc, required this.description, this.tone, this.caption});

  final Dtc dtc;
  final String description;

  /// Defaults to red for active faults and amber for stored ones.
  final Tone? tone;

  /// Extra line, e.g. which ECU reported the code.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = tone ?? (dtc.status == null || dtc.active ? Tone.bad : Tone.warn);
    final color = toneColor(context, effective);
    final flags = dtc.statusFlags;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Text(
              dtc.display,
              style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, color: color),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (dtc.status != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Pill(dtc.active ? 'active' : 'stored', color: color),
                      for (final f in flags.where((f) => f == 'confirmed' || f == 'pending' || f == 'warning lamp'))
                        Pill(f, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ],
                if (caption != null) ...[
                  const SizedBox(height: 4),
                  Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
