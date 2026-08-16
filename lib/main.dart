import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/kinetag_app.dart';
import 'src/app/provider_overrides.dart';

void main() {
  runApp(
    // ProviderScope is the single injection point for the app's services.
    // Swapping the simulator for real hardware later is an override in
    // `kinetagProviderOverrides`, not a change to any screen.
    ProviderScope(
      overrides: kinetagProviderOverrides(),
      child: const KinetagApp(),
    ),
  );
}
