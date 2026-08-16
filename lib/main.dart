import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/kinetag_app.dart';

void main() {
  runApp(
    // ProviderScope is the single injection point for the app's services.
    // Swapping the simulator for real hardware later is an override here,
    // not a change to any screen.
    const ProviderScope(child: KinetagApp()),
  );
}
