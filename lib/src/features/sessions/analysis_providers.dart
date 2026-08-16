import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics_providers.dart';
import '../../analytics/occupancy_grid.dart';
import '../../analytics/team_metrics.dart';
import '../../domain/domain.dart';
import '../settings/settings_controller.dart';
import 'replay_controller.dart';

/// The open session's figures, grouped by team.
///
/// Lives in the sessions feature rather than in `analytics/` because it binds
/// the pure aggregation to *which* session is open — a UI concern. The
/// arithmetic itself stays in [SessionTeamMetrics], usable from a headless
/// export with no providers in sight.
///
/// Derived from [sessionMetricsProvider], so tightening a noise threshold in
/// settings recomputes the team totals exactly as it recomputes a player's.
final sessionTeamMetricsProvider =
    Provider<AsyncValue<SessionTeamMetrics>>((ref) {
  final session = ref.watch(replayControllerProvider.select((s) => s.session));
  if (session == null) {
    return const AsyncValue.data(
      SessionTeamMetrics(teams: [], ranked: [], zonesByTag: {}),
    );
  }

  return ref.watch(sessionMetricsProvider(session.id)).whenData(
        (metrics) =>
            SessionTeamMetrics.from(metrics: metrics, session: session),
      );
});

/// Where the open session's time was spent, per tag.
///
/// Separate from [sessionTeamMetricsProvider] rather than folded into it
/// because the two answer different questions from the same samples, and only
/// one of them is needed to draw a table. A page that never opens a heatmap
/// never builds a grid.
///
/// The grids are built against the session's **own** court, so a recording is
/// always mapped onto the geometry it was captured on.
final sessionOccupancyProvider = FutureProvider<SessionOccupancy>((ref) async {
  final session = ref.watch(replayControllerProvider.select((s) => s.session));
  if (session == null) {
    return SessionOccupancy.empty(court: Court.handball());
  }

  final thresholds = ref.watch(analyticsThresholdsProvider);
  final samples = await ref.watch(sessionSamplesProvider(session.id).future);

  return SessionOccupancy.fromSamples(
    samples,
    court: session.court,
    thresholds: thresholds,
  );
});
