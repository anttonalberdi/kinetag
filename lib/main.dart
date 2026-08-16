import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/kinetag_app.dart';
import 'src/features/setup/setup_state.dart';
import 'src/tracking/tracking_providers.dart';

void main() {
  runApp(
    // ProviderScope is the single injection point for the app's services.
    // Swapping the simulator for real hardware later is an override here,
    // not a change to any screen.
    ProviderScope(
      overrides: [
        // Wire tracking to the court the setup screen is configured for.
        // Done here rather than inside the tracking layer so that layer never
        // depends on a UI feature. `select` keeps the tracking source from
        // being rebuilt every time a receiver is dragged.
        trackingCourtProvider.overrideWith(
          (ref) => ref.watch(setupControllerProvider.select((s) => s.court)),
        ),
      ],
      child: const KinetagApp(),
    ),
  );
}
