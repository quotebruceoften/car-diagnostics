import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';

import 'ui/screens/connect_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/session.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Needed by the background mode (foreground service) used for long jobs.
  FlutterForegroundTask.initCommunicationPort();
  final settings = await AppSettings.load();
  runApp(CarDiagApp(session: DiagSession(settings: settings)));
}

class CarDiagApp extends StatefulWidget {
  const CarDiagApp({super.key, required this.session});
  final DiagSession session;

  @override
  State<CarDiagApp> createState() => _CarDiagAppState();
}

class _CarDiagAppState extends State<CarDiagApp> with WidgetsBindingObserver {
  DiagSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => session.lifecycle = state;

  @override
  Widget build(BuildContext context) => SessionScope(
    session: session,
    child: ListenableBuilder(
      listenable: session.settings,
      builder: (context, _) => MaterialApp(
        title: 'Car Diagnostics',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: session.settings.themeMode,
        home: Builder(
          builder: (context) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: SessionScope.of(context).connected ? const HomeScreen() : const ConnectScreen(),
          ),
        ),
      ),
    ),
  );
}
