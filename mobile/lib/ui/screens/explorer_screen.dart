import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../brands/brand.dart';
import '../../brands/scanner.dart';
import '../../core/error_log.dart';
import '../../core/errors.dart';
import '../../core/transport/transport.dart';
import '../../core/uds/explorer.dart';
import '../../platform/background.dart';
import '../session.dart';
import '../widgets/common.dart';

/// Read-only sweep of the data a module offers, to find where it keeps
/// values such as mileage, fuel level or temperatures.
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key, required this.module, this.partNumber = ''});
  final ModuleDef module;
  final String partNumber;

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  ExplorePreset _preset = explorePresets.first;
  ExploreProgress? _progress;
  bool _running = false;
  bool _cancel = false;
  DateTime? _startedAt;
  Object? _error;
  late DiagSession _session;

  /// Set when the connection dropped mid-sweep; the sweep continues from
  /// here by itself once the app has reconnected.
  ExploreProgress? _interrupted;

  /// Whether background mode started (null: not tried yet).
  bool? _background;

  /// The car this sweep belongs to (kept, because a dropped connection
  /// clears the session).
  String _vin = '';
  String _car = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SessionScope.read(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _session.addListener(_onSession);
    });
  }

  /// Continues an interrupted sweep once the same car is connected again.
  void _onSession() {
    if (!mounted || _interrupted == null || _running || !_session.connected) return;
    if (_session.vin != null && _vin.isNotEmpty && _session.vin != _vin) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _interrupted != null && !_running && _session.connected) _start(resume: _interrupted);
    });
  }

  @override
  void dispose() {
    _cancel = true; // leaving this screen stops the sweep
    _session.removeListener(_onSession);
    if (_interrupted != null) unawaited(_session.background.stop());
    super.dispose();
  }

  Future<void> _start({ExploreProgress? resume}) async {
    setState(() {
      _running = true;
      _cancel = false;
      _error = null;
      _interrupted = null;
      if (resume == null) {
        _progress = null;
        _startedAt = DateTime.now();
        _vin = _session.vin ?? '';
        _car = _session.identity.title;
      }
    });
    final transport = _session.transport;
    // The screen may turn off and the app may go to the background: a
    // notification keeps it running and shows the progress.
    _pace.clear();
    final background = await _session.background.start(
      'Exploring ${widget.module.name}',
      resume == null ? 'Starting...' : 'Continuing after reconnecting...',
    );
    if (!background) {
      final work = _session.background;
      ErrorLog.instance.record(
        'Background mode did not start${work is ForegroundServiceWork && work.lastError != null ? ': ${work.lastError}' : ''}',
      );
    }
    if (mounted) setState(() => _background = background);
    var lastShown = DateTime(0);
    var latest = resume;
    try {
      // A module answers a read within a few hundredths of a second.
      if (transport is AdjustableResponseWait) await (transport as AdjustableResponseWait).setResponseWait(60);
      final uds = ModuleScanner(transport, _session.brand).client(widget.module);
      await for (final p in exploreModule(uds, _preset.ranges, cancelled: () => _cancel, resume: resume)) {
        latest = p;
        if (!mounted) return;
        setState(() => _progress = p);
        if (DateTime.now().difference(lastShown) > const Duration(seconds: 5)) {
          lastShown = DateTime.now();
          unawaited(
            _session.background.update(
              '${p.asked} of ${p.total} asked · ${p.found.length} answered · ${_estimate(p.total - p.asked)} left',
            ),
          );
        }
      }
      if (latest != null && !_cancel && !latest.stoppedResponding) {
        unawaited(
          _session.background.announce(
            'Explorer finished: ${widget.module.name}',
            '${latest.found.length} items answered. Open the app to share the results file.',
          ),
        );
      }
      HapticFeedback.mediumImpact();
    } catch (e) {
      // A dropped connection is not the end: the app reconnects and the sweep continues.
      final lost = !_session.connected || e is TransportException;
      if (mounted) {
        setState(() {
          if (lost && latest != null && !_cancel) {
            _interrupted = latest;
          } else {
            _error = e;
          }
        });
      }
    } finally {
      try {
        if (transport is AdjustableResponseWait && _session.connected) {
          await (transport as AdjustableResponseWait).setResponseWait(null);
        }
      } catch (_) {
        // The adapter went away; the next connection sets it up again.
      }
      // Background mode stays on while waiting to reconnect.
      if (_interrupted == null) await _session.background.stop();
      if (latest != null) await _save(latest);
      if (mounted) setState(() => _running = false);
      if (_interrupted != null) _onSession(); // already reconnected?
    }
  }

  String _resultText(ExploreProgress p) => exploreResultText(
    car: _car.isEmpty ? _session.identity.title : _car,
    module: widget.module.label,
    partNumber: widget.partNumber,
    preset: _preset.name,
    progress: p,
    when: _startedAt ?? DateTime.now(),
  );

  /// Keeps the latest results of each module, for "Send to developer".
  Future<void> _save(ExploreProgress p) async {
    if (p.found.isEmpty && p.locked.isEmpty) return;
    try {
      final store = await _session.dataStore();
      await store.write(
        explorerResultPath(_vin.isEmpty ? (_session.vin ?? '') : _vin, widget.module.address),
        _resultText(p),
      );
    } catch (_) {
      // The results can still be shared from this screen.
    }
  }

  Future<void> _share() async {
    final p = _progress;
    if (p == null) return;
    final text = exploreResultText(
      car: _session.identity.title,
      module: widget.module.label,
      partNumber: widget.partNumber,
      preset: _preset.name,
      progress: p,
      when: _startedAt ?? DateTime.now(),
    );
    final name =
        'explorer-${widget.module.address}-${DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-')}.txt';
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(text), mimeType: 'text/plain', name: name)],
          fileNameOverrides: [name],
          subject: 'Module explorer: ${widget.module.label}',
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not create the file: ${errorText(e)}');
    }
  }

  /// (time, items asked) over the last minute, for the time estimate.
  final _pace = <(DateTime, int)>[];

  /// Rough time for [items] more, from the pace of the last minute (so a slow
  /// stretch in the background does not weigh on it afterwards) or, before
  /// that, a typical adapter.
  String _estimate(int items) {
    final p = _progress;
    var perItem = 0.15;
    if (_running && p != null) {
      final now = DateTime.now();
      _pace
        ..add((now, p.asked))
        ..removeWhere((e) => now.difference(e.$1) > const Duration(seconds: 60));
      final (t0, a0) = _pace.first;
      final seconds = now.difference(t0).inMilliseconds / 1000;
      if (p.asked - a0 >= 20 && seconds > 0) perItem = seconds / (p.asked - a0);
    }
    final seconds = (items * perItem).round();
    return seconds < 90 ? 'about $seconds s' : 'about ${(seconds / 60).round()} min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _progress;
    return Scaffold(
      appBar: AppBar(
        title: Text('Explore · ${widget.module.address.isEmpty ? widget.module.name : widget.module.address}'),
        actions: [
          if (p != null && p.found.isNotEmpty)
            IconButton(tooltip: 'Share results file', icon: const Icon(Icons.ios_share_rounded), onPressed: _share),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.module.name, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Asks this module, one by one, which data items it has and shows every answer. '
                    'It only reads: nothing in the car is changed. You can lock the phone or use other apps '
                    'while it runs; a notification shows the progress and another says when it is done. '
                    'Leaving this screen stops it.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ExplorePreset>(
                      showSelectedIcon: false,
                      segments: [for (final e in explorePresets) ButtonSegment(value: e, label: Text(e.name))],
                      selected: {_preset},
                      onSelectionChanged: _running ? null : (s) => setState(() => _preset = s.first),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_preset.description}: ${_preset.count} items, ${_estimate(_preset.count)}. '
                    'Keep the ignition on.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  if (_running && p != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: p.total == 0 ? null : p.asked / p.total, minHeight: 8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${p.asked} of ${p.total} asked · ${p.found.length} answered · '
                      '${_estimate(p.total - p.asked)} left',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: _running
                        ? OutlinedButton(onPressed: () => setState(() => _cancel = true), child: const Text('Stop'))
                        : FilledButton.icon(
                            icon: const Icon(Icons.travel_explore_rounded),
                            label: Text(p == null ? 'Start' : 'Run again'),
                            onPressed: _session.connected ? () => _start() : null,
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorPanel(error: _error!),
            ),
          if (_interrupted case final i?)
            StatusBanner(
              tone: Tone.warn,
              icon: Icons.link_off_rounded,
              title: 'Connection lost at ${i.asked} of ${i.total}',
              subtitle: 'The app is reconnecting; the sweep then continues from there by itself.',
              action: TextButton(
                onPressed: _session.connected ? () => _start(resume: i) : null,
                child: const Text('Continue'),
              ),
            ),
          if (_background == false)
            const StatusBanner(
              tone: Tone.warn,
              icon: Icons.phonelink_lock_outlined,
              title: 'Background mode is off',
              subtitle:
                  'Android did not allow it, so keep the app open on this screen. Check that notifications '
                  'are allowed for Car Diagnostics.',
            )
          else if (_background == true && _running)
            const StatusBanner(
              tone: Tone.ok,
              icon: Icons.phonelink_lock_outlined,
              title: 'Background mode is on',
              subtitle: 'You can lock the phone or use other apps; a notification shows the progress.',
            ),
          if (p != null && p.stoppedResponding && !_running)
            StatusBanner(
              tone: Tone.warn,
              icon: Icons.info_outline_rounded,
              title: 'The module stopped responding at ${p.asked} of ${p.total}',
              subtitle: 'It may have gone to sleep. Turn the ignition on, then continue from there.',
              action: TextButton(
                onPressed: _session.connected ? () => _start(resume: p) : null,
                child: const Text('Continue'),
              ),
            ),
          if (p != null && !_running && p.found.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.ios_share_rounded),
                label: Text('Share results file (${p.found.length} items)'),
                onPressed: _share,
              ),
            ),
          if (p != null && p.found.isNotEmpty) ...[
            SectionHeader('Answered (${p.found.length})'),
            Card(
              child: Column(
                children: [
                  // The newest answers first while it runs; the list can get long.
                  for (final item in (_running ? p.found.reversed.take(30) : p.found.take(400)))
                    ListTile(
                      dense: true,
                      leading: Text(item.id, style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'monospace')),
                      title: Text(
                        item.text ?? (item.number != null ? '${item.number}' : '${item.data.length} bytes'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.hex,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: '${item.id} ${item.hex}'));
                        showMessage(context, 'Copied');
                      },
                    ),
                ],
              ),
            ),
            if (!_running && p.found.length > 400)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Showing the first 400. The results file has all ${p.found.length}.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          if (p != null && !_running && p.found.isEmpty && !p.stoppedResponding && _interrupted == null)
            const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing answered',
              message: 'The module has no readable items in this range. Try a wider sweep.',
            ),
        ],
      ),
    );
  }
}
