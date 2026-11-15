/// The most recent error messages the app showed, for "Send to developer".
class ErrorLog {
  ErrorLog._();
  static final instance = ErrorLog._();

  static const _keep = 40;
  final _entries = <(DateTime, String)>[];

  List<(DateTime, String)> get entries => List.unmodifiable(_entries);

  /// Records [message]. The same message again within two minutes counts as
  /// one (error panels are redrawn many times).
  void record(String message, {DateTime? at}) {
    final now = at ?? DateTime.now();
    for (final (t, m) in _entries.reversed) {
      if (now.difference(t) > const Duration(minutes: 2)) break;
      if (m == message) return;
    }
    _entries.add((now, message));
    if (_entries.length > _keep) _entries.removeRange(0, _entries.length - _keep);
  }

  void clear() => _entries.clear();
}
