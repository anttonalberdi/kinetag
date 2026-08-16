import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not part of flutter_riverpod's main export; misc.dart is where
// Riverpod 3 publishes it.
import 'package:riverpod/misc.dart';

import '../features/settings/settings_controller.dart';
import '../features/setup/roster_state.dart';
import '../features/setup/setup_state.dart';
import '../tracking/simulator/simulated_squad.dart';
import '../tracking/tracking_providers.dart';

/// Points the tracking layer at what the UI has been configured with.
///
/// These overrides live in the app layer, not in the tracking layer, so that
/// tracking never depends on a UI feature: it declares what it needs (a court,
/// a squad, a sample rate) and the application decides where those come from.
/// Swapping the simulator for real hardware later replaces entries in this
/// list and touches no screen.
///
/// Shared with the tests rather than duplicated there, so what is verified is
/// the wiring the app actually runs.
List<Override> kinetagProviderOverrides() => [
      // Wire tracking to the court the setup screen is configured for.
      // `select` keeps the tracking source from being rebuilt every time a
      // receiver is dragged.
      trackingCourtProvider.overrideWith(
        (ref) => ref.watch(setupControllerProvider.select((s) => s.court)),
      ),

      // Simulate exactly the tags the operator defined in setup.
      //
      // The body re-runs on every roster edit, but `SimulatedSquad` compares
      // equal when the simulated movement is unchanged, and a provider that
      // recomputes to an equal value notifies nobody. That is what stops a
      // rename from tearing down the tracking source — possibly mid-recording
      // — underneath the live view.
      simulatedSquadProvider.overrideWith((ref) {
        final roster = ref.watch(rosterControllerProvider);
        return SimulatedSquad.fromRoster(
          players: roster.players,
          tags: roster.tags,
          assignments: roster.assignments,
          // The line-up decides which of those tags are fielded and which are
          // simulated on the bench. It comes from settings rather than from
          // the roster because it is a property of the game being played, not
          // of who turned up.
          fieldPlayersOnCourt: ref.watch(
            appSettingsProvider.select((s) => s.fieldPlayersOnCourt),
          ),
        );
      }),

      trackingSampleRateProvider.overrideWith(
        (ref) => ref.watch(appSettingsProvider.select((s) => s.captureRateHz)),
      ),
    ];
