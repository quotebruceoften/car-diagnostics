import 'package:flutter/material.dart';

import 'ui/screens/connect_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/session.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(CarDiagApp(session: DiagSession(settings: settings)));
}

class CarDiagApp extends StatelessWidget {
  const CarDiagApp({super.key, required this.session});
  final DiagSession session;

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
