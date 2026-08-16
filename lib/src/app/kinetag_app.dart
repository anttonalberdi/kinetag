import 'package:flutter/material.dart';

import 'app_shell.dart';

/// Root widget. Owns theming only; all navigation lives in [AppShell].
class KinetagApp extends StatelessWidget {
  const KinetagApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F6F4A),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Kinetag',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        visualDensity: VisualDensity.comfortable,
      ),
      home: const AppShell(),
    );
  }
}
