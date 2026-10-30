import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/obd/dtc.dart';
import '../../core/obd/dtc_info.dart';
import '../session.dart';
import '../widgets/common.dart';

Tone severityTone(Severity s) => switch (s) {
  Severity.low => Tone.ok,
  Severity.medium => Tone.warn,
  Severity.high || Severity.critical => Tone.bad,
};

/// Everything about one fault code in plain language.
class DtcScreen extends StatelessWidget {
  const DtcScreen({super.key, required this.dtc, required this.description, this.source});

  final Dtc dtc;

  /// The short description from the make or the generic table.
  final String description;

  /// Which module or ECU reported it.
  final String? source;

  Future<void> _search(BuildContext context, String car) async {
    final query = Uri.encodeQueryComponent('${dtc.code} $car');
    final ok = await launchUrl(
      Uri.parse('https://www.google.com/search?q=$query'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) showMessage(context, 'Could not open the browser');
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final info = dtcInfo(dtc.code);
    final theme = Theme.of(context);
    final tone = severityTone(info.severity);
    final color = toneColor(context, tone);
    return Scaffold(
      appBar: AppBar(title: Text(dtc.display)),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          dtc.display,
                          style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'monospace', color: color),
                        ),
                      ),
                      const Spacer(),
                      if (dtc.status != null)
                        Pill(
                          dtc.active ? 'active now' : 'stored',
                          color: dtc.active ? color : theme.colorScheme.outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(info.isGeneric ? description : info.title, style: theme.textTheme.titleLarge),
                  if (source != null) ...[
                    const SizedBox(height: 4),
                    Text('Reported by $source', style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          StatusBanner(
            tone: tone,
            icon: switch (info.severity) {
              Severity.low => Icons.info_outline_rounded,
              Severity.medium => Icons.build_circle_outlined,
              Severity.high => Icons.warning_amber_rounded,
              Severity.critical => Icons.dangerous_outlined,
            },
            title: info.severity.label,
            subtitle: info.severity.advice,
          ),
          const SectionHeader('What it means'),
          _TextCard(info.meaning),
          if (info.causes.isNotEmpty) ...[
            const SectionHeader('Common causes'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    for (final c in info.causes)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
                        minLeadingWidth: 12,
                        title: Text(c, style: theme.textTheme.bodyMedium),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SectionHeader('Can I drive?'),
          _TextCard(info.driving),
          if (dtc.statusFlags.isNotEmpty) ...[
            const SectionHeader('Status reported by the module'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final f in dtc.statusFlags) Pill(f, color: theme.colorScheme.onSurfaceVariant)],
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.travel_explore_rounded),
              label: Text('Search "${dtc.code} ${session.identity.name}"'),
              onPressed: () => _search(context, session.identity.name),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'General guidance, not a diagnosis. The same code can have different causes on different engines.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}

/// Opens the detail page for [dtc].
void openDtc(BuildContext context, Dtc dtc, String description, {String? source}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => DtcScreen(dtc: dtc, description: description, source: source),
  ),
);
