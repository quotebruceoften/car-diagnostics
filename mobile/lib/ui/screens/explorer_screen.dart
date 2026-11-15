import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../brands/brand.dart';
import '../../brands/scanner.dart';
import '../../core/transport/transport.dart';
import '../../core/uds/explorer.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SessionScope.read(context);
  }

  @override
  void dispose() {
    _cancel = true;
    keepScreenOn(false);
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _cancel = false;
      _error = null;
      _progress = null;
      _startedAt = DateTime.now();
    });
    keepScreenOn(true);
    final transport = _session.transport;
    try {
      // A module answers a read within a few hundredths of a second.
      if (transport is AdjustableResponseWait) await (transport as AdjustableResponseWait).setResponseWait(60);
      final uds = ModuleScanner(transport, _session.brand).client(widget.module);
      await for (final p in exploreModule(uds, _preset.ranges, cancelled: () => _cancel || !_session.connected)) {
        if (!mounted) return;
        setState(() => _progress = p);
      }
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      try {
        if (transport is AdjustableResponseWait && _session.connected) {
          await (transport as AdjustableResponseWait).setResponseWait(null);
        }
      } catch (_) {
        // The adapter went away; the next connection sets it up again.
      }
      keepScreenOn(false);
      if (mounted) setState(() => _running = false);
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

  /// Rough time for a sweep, from the pace so far or a typical adapter.
  String _estimate(int items) {
    final p = _progress, started = _startedAt;
    var perItem = 0.15;
    if (_running && p != null && started != null && p.asked > 20) {
      perItem = DateTime.now().difference(started).inMilliseconds / 1000 / p.asked;
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
                    'It only reads: nothing in the car is changed.',
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
                            onPressed: _session.connected ? _start : null,
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
          if (p != null && p.stoppedResponding)
            const StatusBanner(
              tone: Tone.warn,
              icon: Icons.info_outline_rounded,
              title: 'The module stopped responding',
              subtitle: 'It may have gone to sleep. Turn the ignition on and run it again.',
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
          if (p != null && !_running && p.found.isEmpty && !p.stoppedResponding)
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
