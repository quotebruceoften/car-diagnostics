import 'package:flutter/material.dart';

import 'ui/screens/connect_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/session.dart';

void main() => runApp(CarDiagApp(session: DiagSession()));

class CarDiagApp extends StatelessWidget {
  const CarDiagApp({super.key, required this.session});
  final DiagSession session;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E8C), brightness: b),
      useMaterial3: true,
    );
    return SessionScope(
      session: session,
      child: MaterialApp(
        title: 'Car Diagnostics',
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        home: Builder(
          builder: (context) => SessionScope.of(context).connected ? const HomeScreen() : const ConnectScreen(),
        ),
      ),
    );
  }
}
