import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics_providers.dart';
import '../../analytics/occupancy_grid.dart';
import '../../analytics/play_metrics.dart';
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

/// The open session segmented into playing time, bench time and phases of
/// play.
///
/// Built on [sessionMetricsProvider] rather than beside it, so the
/// whole-recording figures the replay panel reads and the split figures the
/// analysis pages read are the same arithmetic over different intervals — they
/// refine each other and can never disagree.
final sessionPlayMetricsProvider = FutureProvider<SessionPlayMetrics>((
  ref,
) async {
  final session = ref.watch(replayControllerProvider.select((s) => s.session));
  if (session == null) return SessionPlayMetrics.empty(Court.handball());

  final metrics = await ref.watch(sessionMetricsProvider(session.id).future);
  final samples = await ref.watch(sessionSamplesProvider(session.id).future);

  return SessionPlayMetrics.from(
    metrics: metrics,
    samples: samples,
    session: session,
  );
});

/// Which stretch of the recording the analysis pages are reporting on.
///
/// State rather than a parameter because it is a reading position, not a
/// property of the data: switching to "Attacking" should re-scope the team
/// cards, the ranking and the player pages together, and a reader who picked a
/// split before opening a player expects to still be in it when they come
/// back.
class PlaySplitController extends Notifier<PlaySplit> {
  @override
  PlaySplit build() => PlaySplit.onCourt;

  void select(PlaySplit split) => state = split;
}

/// Defaults to [PlaySplit.onCourt]: bench time is excluded from every figure
/// unless a reader deliberately asks otherwise, because a squad total that
/// silently counts substitutes sitting down is the figure most likely to be
/// misread.
final playSplitProvider = NotifierProvider<PlaySplitController, PlaySplit>(
  PlaySplitController.new,
);

/// The open session grouped by team, scoped to the selected split.
///
/// Distinct from [sessionTeamMetricsProvider], which stays whole-recording for
/// the replay panel's sake. This is what every analysis page reads, so changing
/// the split changes the whole report at once.
final splitTeamMetricsProvider = Provider<AsyncValue<SessionTeamMetrics>>((
  ref,
) {
  final session = ref.watch(replayControllerProvider.select((s) => s.session));
  final split = ref.watch(playSplitProvider);

  if (session == null) {
    return const AsyncValue.data(
      SessionTeamMetrics(teams: [], ranked: [], zonesByTag: {}),
    );
  }

  return ref.watch(sessionPlayMetricsProvider).whenData(
        (play) => SessionTeamMetrics.fromTracks(
          tracks: play.tracksFor(split),
          session: session,
          thresholds: play.thresholds,
        ),
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
