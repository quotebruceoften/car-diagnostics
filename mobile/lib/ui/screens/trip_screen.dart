import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../core/trip.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/alert_banner.dart';
import '../widgets/common.dart';

enum _FuelSource { fuelRate, maf, none }

String tripsPath(String vin) => 'trips/${vin.isEmpty ? 'unknown' : vin}.json';

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m ${s.toString().padLeft(2, '0')}s';
}

/// Asks for the fuel price and currency symbol.
Future<void> editFuelPrice(BuildContext context) async {
  final settings = SessionScope.read(context).settings;
  final price = TextEditingController(text: settings.fuelPrice?.toStringAsFixed(3) ?? '');
  final currency = TextEditingController(text: settings.currency);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Fuel price'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: price,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Price per litre', hintText: 'e.g. 1.789'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: currency,
            decoration: const InputDecoration(labelText: 'Currency symbol (optional)', hintText: 'e.g. €, \$, £'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok == true) {
    settings.setFuelPrice(double.tryParse(price.text.trim().replaceAll(',', '.')), currency.text.trim());
  }
  price.dispose();
  currency.dispose();
}

/// Live fuel consumption and the distance, fuel and cost of a drive.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  _FuelSource? _source;
  bool _diesel = false;
  TripComputer? _trip;
  List<TripRecord> _saved = [];
  Object? _error;
  bool _polling = false;

  late DiagSession _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SessionScope.read(context);
    if (_source == null && _error == null) _setUp();
  }

  @override
  void dispose() {
    keepScreenOn(false);
    super.dispose();
  }

  Future<void> _setUp() async {
    try {
      final supported = (await _session.obd.supportedPids()).values.expand((s) => s).toSet();
      try {
        _diesel = (await _session.obd.readiness()).diesel;
      } on CarDiagException {
        _diesel = false;
      }
      final store = await _session.dataStore();
      final saved = TripRecord.listFromJson(await store.read(tripsPath(_session.vin ?? '')));
      if (!mounted) return;
      setState(() {
        _saved = saved.reversed.toList();
        _source = supported.contains(0x5E)
            ? _FuelSource.fuelRate
            : (supported.contains(0x10) && !_diesel ? _FuelSource.maf : _FuelSource.none);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _start() {
    HapticFeedback.mediumImpact();
    keepScreenOn(true);
    setState(() => _trip = TripComputer(DateTime.now()));
    _poll();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      while (mounted && _trip != null && _trip!.end == null && _session.connected) {
        try {
          final speed = await _session.obd.read('speed');
          _session.observe(speed.pid, speed.value);
          double rate = 0;
          switch (_source) {
            case _FuelSource.fuelRate:
              rate = (await _session.obd.read('fuel_rate')).numeric ?? 0;
            case _FuelSource.maf:
              rate = litresPerHourFromMaf((await _session.obd.read('maf')).numeric ?? 0);
            case _FuelSource.none || null:
              break;
          }
          if (!mounted || _trip == null) break;
          setState(() {
            _trip!.add(DateTime.now(), speed.numeric ?? 0, rate);
            _error = null;
          });
        } on NoResponseException catch (e) {
          if (mounted) setState(() => _error = e);
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _polling = false;
    }
  }

  Future<void> _stop() async {
    final trip = _trip;
    if (trip == null) return;
    HapticFeedback.mediumImpact();
    keepScreenOn(false);
    final record = trip.finish(DateTime.now(), pricePerLitre: _session.settings.fuelPrice);
    setState(() => _trip = null);
    if (record.distanceKm < 0.01 && record.fuelLitres < 0.001) return;
    final store = await _session.dataStore();
    final path = tripsPath(_session.vin ?? '');
    final all = [...TripRecord.listFromJson(await store.read(path)), record];
    await store.write(path, jsonEncode([for (final t in all) t.toJson()]));
    if (mounted) setState(() => _saved = all.reversed.toList());
  }

  Future<void> _delete(TripRecord r) async {
    final store = await _session.dataStore();
    final path = tripsPath(_session.vin ?? '');
    final all = TripRecord.listFromJson(await store.read(path))
      ..removeWhere((t) => t.start == r.start && t.end == r.end);
    await store.write(path, jsonEncode([for (final t in all) t.toJson()]));
    if (mounted) setState(() => _saved = all.reversed.toList());
  }

  String _economy(AppSettings s, double litres, double km) {
    final v = s.economy.convert(litres, km);
    return v == null ? '–' : '${v.toStringAsFixed(1)} ${s.economy.label}';
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final settings = session.settings;
    final theme = Theme.of(context);
    final trip = _trip;
    final hasFuel = _source == _FuelSource.fuelRate || _source == _FuelSource.maf;

    String instant() {
      if (trip == null || !hasFuel) return '–';
      if (trip.speedKmh < 3) return '${trip.litresPerHour.toStringAsFixed(1)} L/h';
      // Litres per hour over km per hour is litres per km.
      return _economy(settings, trip.litresPerHour, trip.speedKmh);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip computer'),
        actions: [
          IconButton(
            tooltip: 'Fuel price',
            icon: const Icon(Icons.local_gas_station_outlined),
            onPressed: () => editFuelPrice(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const AlertBanner(),
          Expanded(
            child: _source == null && _error == null
                ? const LoadingView(message: 'Checking which sensors the car has...')
                : ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 32),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: ErrorPanel(error: _error!),
                        ),
                      if (_source == _FuelSource.none)
                        StatusBanner(
                          tone: Tone.warn,
                          icon: Icons.info_outline_rounded,
                          title: 'Distance only',
                          subtitle: _diesel
                              ? "This diesel doesn't report its fuel rate, and air flow can't be used for diesels. "
                                    'Distance and time are still recorded.'
                              : "The car reports neither fuel rate nor air flow, so fuel use can't be measured.",
                        ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Text(
                                trip == null ? 'Ready' : (trip.speedKmh < 3 ? 'Standing' : 'Now'),
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                child: Text(
                                  instant(),
                                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (trip != null) ...[
                                const SizedBox(height: 4),
                                Text(settings.speed(trip.speedKmh), style: theme.textTheme.titleMedium),
                              ],
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: trip == null
                                    ? FilledButton.icon(
                                        icon: const Icon(Icons.play_arrow_rounded),
                                        label: const Text('Start trip'),
                                        onPressed: session.connected ? _start : null,
                                      )
                                    : FilledButton.icon(
                                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
                                        icon: const Icon(Icons.stop_rounded),
                                        label: const Text('End trip'),
                                        onPressed: _stop,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (trip != null)
                        TileGrid(
                          children: [
                            StatTile(icon: Icons.route_rounded, label: 'Distance', value: settings.km(trip.distanceKm)),
                            StatTile(icon: Icons.timer_outlined, label: 'Time', value: formatDuration(trip.elapsed)),
                            if (hasFuel) ...[
                              StatTile(
                                icon: Icons.local_gas_station_rounded,
                                label: 'Average',
                                value: _economy(settings, trip.fuelLitres, trip.distanceKm),
                              ),
                              StatTile(
                                icon: Icons.water_drop_outlined,
                                label: settings.fuelPrice == null ? 'Fuel used' : 'Fuel used · cost',
                                value: settings.fuelPrice == null
                                    ? '${trip.fuelLitres.toStringAsFixed(2)} L'
                                    : '${trip.fuelLitres.toStringAsFixed(2)} L · '
                                          '${settings.money(trip.fuelLitres * settings.fuelPrice!)}',
                              ),
                            ],
                            StatTile(
                              icon: Icons.speed_rounded,
                              label: 'Average speed',
                              value: settings.speed(trip.averageSpeed),
                            ),
                            StatTile(
                              icon: Icons.trending_up_rounded,
                              label: 'Top speed',
                              value: settings.speed(trip.maxSpeed),
                            ),
                          ],
                        ),
                      if (hasFuel && settings.fuelPrice == null)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.payments_outlined),
                            title: const Text('Add your fuel price'),
                            subtitle: const Text('to see what each drive costs'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => editFuelPrice(context),
                          ),
                        ),
                      if (_saved.isNotEmpty) ...[
                        const SectionHeader('Past trips'),
                        for (final r in _saved)
                          Dismissible(
                            key: ValueKey(r.start),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 32),
                              child: Icon(Icons.delete_outline_rounded, color: toneColor(context, Tone.bad)),
                            ),
                            onDismissed: (_) => _delete(r),
                            child: Card(
                              child: ListTile(
                                title: Text(
                                  '${settings.km(r.distanceKm)} · ${formatDuration(r.duration)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  [
                                    formatTimestamp(r.start),
                                    if (r.fuelLitres > 0) _economy(settings, r.fuelLitres, r.distanceKm),
                                    if (r.fuelLitres > 0) '${r.fuelLitres.toStringAsFixed(2)} L',
                                  ].join(' · '),
                                ),
                                trailing: r.cost == null
                                    ? null
                                    : Text(settings.money(r.cost!), style: theme.textTheme.titleMedium),
                              ),
                            ),
                          ),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                        child: Text(
                          'Keep this screen open while driving. Fuel use is worked out from the engine\'s sensors '
                          'and is usually within 5-10% of the pump.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
