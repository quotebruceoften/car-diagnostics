import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session.dart';
import '../settings.dart';
import '../widgets/common.dart';

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
            const SectionHeader('About'),
            const Card(
              child: Column(
                children: [
                  InfoRow('Version', '0.2.0'),
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
