import 'package:flutter/material.dart';

import '../../core/obd/readiness.dart';
import '../session.dart';
import '../widgets/common.dart';

(Tone, IconData, String, String) describeVerdict(Readiness r) => switch (r.verdict) {
  ReadinessVerdict.ready => (
    Tone.ok,
    Icons.verified_rounded,
    'Ready for inspection',
    'All emissions self-tests have completed.',
  ),
  ReadinessVerdict.almostReady => (
    Tone.warn,
    Icons.hourglass_bottom_rounded,
    'Probably ready',
    'One self-test has not finished. Many inspections accept one; some do not.',
  ),
  ReadinessVerdict.notReady when r.milOn => (
    Tone.bad,
    Icons.warning_rounded,
    'Not ready',
    'The check engine light is on, which fails an inspection.',
  ),
  ReadinessVerdict.notReady => (
    Tone.bad,
    Icons.pending_actions_rounded,
    'Not ready yet',
    '${r.incomplete.length} self-tests have not finished.',
  ),
};

/// Which emissions self-tests have completed, as an inspection would check.
class ReadinessScreen extends StatelessWidget {
  const ReadinessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection readiness')),
      body: AsyncLoader<Readiness>(
        load: () => session.obd.readiness(),
        builder: (context, r, reload) {
          final (tone, icon, title, subtitle) = describeVerdict(r);
          final theme = Theme.of(context);
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 32),
              children: [
                StatusBanner(tone: tone, icon: icon, title: title, subtitle: subtitle),
                const SectionHeader('Self-tests'),
                Card(
                  child: Column(
                    children: [
                      for (final m in r.monitors)
                        ListTile(
                          leading: Icon(
                            m.complete ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: toneColor(context, m.complete ? Tone.ok : Tone.warn),
                          ),
                          title: Text(m.name),
                          subtitle: m.continuous ? const Text('Runs continuously while driving') : null,
                          trailing: Text(
                            m.complete ? 'Complete' : 'Not finished',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: toneColor(context, m.complete ? Tone.ok : Tone.warn),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (r.incomplete.isNotEmpty) ...[
                  const SectionHeader('How to finish them'),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Self-tests reset when fault codes are cleared or the battery is disconnected. They finish '
                        'by themselves with normal driving: usually a few days of mixed driving including a cold '
                        'start, some steady motorway speed and some town driving. Some tests (like the fuel vapour '
                        'test) also need the fuel tank between a quarter and three-quarters full.',
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                  child: Text(
                    '${r.diesel ? 'Diesel' : 'Petrol'} engine. Inspection rules vary by country; this is a guide, '
                    'not an official result.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
