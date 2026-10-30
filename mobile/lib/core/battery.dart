/// Grading for the battery and charging test. Voltages are measured by the
/// adapter at the OBD port, which is close to the battery's own voltage.
library;

enum Grade { good, fair, bad }

class Verdict {
  const Verdict(this.grade, this.title, this.detail);
  final Grade grade;
  final String title;
  final String detail;
}

/// Engine off, ignition on.
Verdict gradeResting(double v) {
  if (v >= 12.45) {
    return const Verdict(Grade.good, 'Well charged', 'A healthy, charged battery reads about 12.5-12.8 V at rest.');
  }
  if (v >= 12.2) {
    return const Verdict(
      Grade.fair,
      'Partly charged',
      'Around 60-75% charged. Short trips may not be keeping it topped up; a longer drive or a charger helps.',
    );
  }
  if (v >= 11.9) {
    return const Verdict(
      Grade.bad,
      'Low',
      'The battery is low. Charge it fully and test again; if it drops back within a day, it is likely worn.',
    );
  }
  return const Verdict(
    Grade.bad,
    'Flat or failing',
    'Below 11.9 V the battery is close to flat. Starting may fail; charge it and have it load-tested.',
  );
}

/// Lowest voltage while the starter turns the engine.
Verdict gradeCranking(double minimum) {
  if (minimum >= 10.0) {
    return const Verdict(Grade.good, 'Strong start', 'The voltage stayed above 10 V while cranking.');
  }
  if (minimum >= 9.6) {
    return const Verdict(
      Grade.fair,
      'Acceptable',
      'The voltage dipped close to the 9.6 V limit. Fine in summer; it may struggle on cold mornings.',
    );
  }
  return const Verdict(
    Grade.bad,
    'Weak',
    'The voltage fell below 9.6 V while cranking. The battery is likely worn or discharged, or a cable or '
        'terminal is corroded.',
  );
}

/// Engine running.
Verdict gradeCharging(double average) {
  if (average > 15.0) {
    return const Verdict(
      Grade.bad,
      'Overcharging',
      'Above 15 V can damage the battery and electronics. Have the alternator regulator checked.',
    );
  }
  if (average >= 13.2) {
    return const Verdict(Grade.good, 'Charging normally', 'The alternator is charging the battery.');
  }
  if (average >= 12.6) {
    return const Verdict(
      Grade.fair,
      'Low charging voltage',
      'Many modern cars, including VWs with energy management, lower the charging voltage when the battery is '
          'full, so this can be normal. Turn on the headlights and fan and test again: it should rise above 13 V.',
    );
  }
  return const Verdict(
    Grade.bad,
    'Not charging',
    'With the engine running the voltage should be well above the battery\'s own 12.5 V. Check the '
        'alternator, its belt and fuse.',
  );
}

/// Finds the cranking dip in voltage samples taken while starting.
/// Returns null when no start was seen (no clear dip below [resting]).
double? crankingMinimum(List<double> samples, double resting) {
  if (samples.isEmpty) return null;
  final minimum = samples.reduce((a, b) => a < b ? a : b);
  return resting - minimum >= 0.5 ? minimum : null;
}
