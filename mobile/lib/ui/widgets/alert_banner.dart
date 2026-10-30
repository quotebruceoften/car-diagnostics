import 'package:flutter/material.dart';

import '../../core/alerts.dart';
import '../../core/obd/pids.dart';
import '../session.dart';
import '../settings.dart';

/// Explains why an alert fired, in the user's units.
String describeAlert(ActiveAlert a, AppSettings settings) {
  final pid = pidsByName[a.rule.pid];
  if (pid == null) return a.rule.pid;
  final above = a.rule.above != null && a.value > a.rule.above!;
  final limit = above ? a.rule.above! : (a.rule.below ?? 0);
  return '${pid.description} ${settings.format(pid, a.value)}: '
      '${above ? 'above' : 'below'} ${settings.format(pid, limit)}';
}

/// Red bars for the live-data alerts that are on.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, this.dark = false});

  /// For the black driving dashboard.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return ListenableBuilder(
      listenable: session.alerts,
      builder: (context, _) {
        final active = session.alerts.active;
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in active)
                Material(
                  color: const Color(0xFFC62828),
                  child: SafeArea(
                    top: !dark,
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              describeAlert(a, session.settings),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss',
                            color: Colors.white,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => session.alerts.dismiss(a.rule.pid),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
