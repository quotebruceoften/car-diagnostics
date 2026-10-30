import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data_backup.dart';
import '../../core/trip.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/common.dart';
import 'alerts_screen.dart';
import 'trip_screen.dart';

Future<void> _backUp(BuildContext context) async {
  final session = SessionScope.read(context);
  try {
    final text = await exportData(await session.dataStore(), session.settings.toJson());
    final name = 'car-diagnostics-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(utf8.encode(text), mimeType: 'application/json', name: name)],
        fileNameOverrides: [name],
        subject: 'Car Diagnostics backup',
      ),
    );
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not create the backup: ${errorText(e)}');
  }
}

Future<void> _restore(BuildContext context) async {
  final session = SessionScope.read(context);
  try {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Choose a Car Diagnostics backup');
    if (picked.isEmpty) return;
    final text = utf8.decode(await picked.first.readAsBytes(), allowMalformed: true);
    final result = await importData(await session.dataStore(), text);
    session.settings.applyJson(result.settings);
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      final n = result.added + result.updated;
      showMessage(context, n == 0 ? 'Settings restored; no new records' : 'Restored $n record${n == 1 ? '' : 's'}');
    }
  } on FormatException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not restore: ${errorText(e)}');
  }
}

/// Set by the CI build, so the build can be matched to its download.
const _build = String.fromEnvironment('BUILD_NUMBER');
const _version = _build == '' ? '0.3.0' : '0.3.0 (build $_build)';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SessionScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SectionHeader('Appearance'),
            _Choice<ThemeMode>(
              icon: Icons.brightness_6_outlined,
              title: 'Theme',
              value: settings.themeMode,
              options: const {ThemeMode.system: 'Automatic', ThemeMode.light: 'Light', ThemeMode.dark: 'Dark'},
              onChanged: settings.setThemeMode,
            ),
            const SectionHeader('Units'),
            _Choice<TempUnit>(
              icon: Icons.thermostat_rounded,
              title: 'Temperature',
              value: settings.temp,
              options: const {TempUnit.celsius: '°C', TempUnit.fahrenheit: '°F'},
              onChanged: settings.setTemp,
            ),
            _Choice<DistanceUnit>(
              icon: Icons.straighten_rounded,
              title: 'Distance and speed',
              value: settings.distance,
              options: const {DistanceUnit.km: 'km · km/h', DistanceUnit.miles: 'miles · mph'},
              onChanged: settings.setDistance,
            ),
            _Choice<EconomyUnit>(
              icon: Icons.local_gas_station_outlined,
              title: 'Fuel economy',
              value: settings.economy,
              options: const {
                EconomyUnit.lPer100km: 'L/100km',
                EconomyUnit.kmPerL: 'km/L',
                EconomyUnit.mpgUs: 'US mpg',
                EconomyUnit.mpgUk: 'UK mpg',
              },
              onChanged: settings.setEconomy,
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Fuel price'),
                    subtitle: Text(
                      settings.fuelPrice == null ? 'Not set' : '${settings.money(settings.fuelPrice!)} per litre',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => editFuelPrice(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Live data alerts'),
                    subtitle: Text('${settings.alertRules.where((r) => r.enabled).length} on'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AlertsScreen())),
                  ),
                ],
              ),
            ),
            const SectionHeader('Notifications'),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Service reminders'),
                subtitle: const Text('A notification a week before and on the day a service is due'),
                value: settings.serviceNotifications,
                onChanged: (v) async {
                  HapticFeedback.selectionClick();
                  final session = SessionScope.read(context);
                  settings.setServiceNotifications(v);
                  if (!v) {
                    await session.notifier.cancelAll();
                  } else if (settings.lastCar case final car?) {
                    await session.syncServiceNotifications(car.vin);
                  }
                },
              ),
            ),
            const SectionHeader('Connection'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.bluetooth_connected_rounded),
                    title: const Text('Reconnect automatically'),
                    subtitle: const Text('Connect to your last adapter when the app opens'),
                    value: settings.autoReconnect,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      settings.setAutoReconnect(v);
                    },
                  ),
                  if (settings.lastAdapter case final a?)
                    ListTile(
                      leading: const Icon(Icons.link_off_rounded),
                      title: Text('Forget ${a.name}'),
                      subtitle: Text(a.detail),
                      onTap: () {
                        settings.setLastAdapter(null);
                        showMessage(context, 'Adapter forgotten');
                      },
                    ),
                ],
              ),
            ),
            const SectionHeader('Your data'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Back up all data'),
                    subtitle: const Text(
                      'Scan history, coding backups, service log, trips, timer results and settings in one file',
                    ),
                    onTap: () => _backUp(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore_rounded),
                    title: const Text('Restore from a backup'),
                    subtitle: const Text('Adds what is missing; nothing on this phone is deleted'),
                    onTap: () => _restore(context),
                  ),
                ],
              ),
            ),
            const SectionHeader('About'),
            const Card(
              child: Column(
                children: [
                  InfoRow('Version', _version),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Text(
                      'Diagnostics and coding for OBD-II cars, with module scanning and long coding for '
                      'Volkswagen Group cars. Changing coding is at your own risk; the app backs up and '
                      'verifies every write.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled segmented choice inside a card.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> options;
  final void Function(T) onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
              selected: {value},
              onSelectionChanged: (s) {
                HapticFeedback.selectionClick();
                onChanged(s.first);
              },
            ),
          ),
        ],
      ),
    ),
  );
}
