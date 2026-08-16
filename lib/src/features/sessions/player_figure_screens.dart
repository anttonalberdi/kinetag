import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/session_metrics.dart';
import '../../analytics/speed_zones.dart';
import '../../analytics/team_metrics.dart';
import '../../core/duration_format.dart';
import '../../core/metric_format.dart';
import '../court/tag_roster.dart';
import 'analysis_navigation.dart';
import 'analysis_providers.dart';
import 'analysis_widgets.dart';
import 'heatmap_panel.dart';
import 'replay_controller.dart';
import 'replay_screen.dart';

/// A player's floor map, at the size the thumbnail on their page cannot be.
///
/// A page rather than the dialog a team card opens: this is somewhere the
/// reader navigated to from one player's own page, and the trail back through
/// that player to the session is worth keeping visible.
class PlayerHeatmapScreen extends ConsumerWidget {
  final String tagId;
  final VoidCallback onBackToSessions;

  /// Wide enough to read a court on, narrow enough that a 2:1 court does not
  /// push everything under it off a desktop screen.
  static const double _maxFigureWidth = 920;

  const PlayerHeatmapScreen({
    super.key,
    required this.tagId,
    required this.onBackToSessions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlayerFigureScaffold(
        tagId: tagId,
        crumb: 'Movement map',
        onBackToSessions: onBackToSessions,
        builder: (context, figure) => ListView(
          children: [
            const SectionTitle(
              title: 'Where the time was spent',
              description: 'Brighter squares are the ones this player stood '
                  'in longest. The ramp is normalised against this map’s own '
                  'busiest square, so the same colour means different amounts '
                  'of time on two different maps — the figures below are what '
                  'compares between players.',
            ),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _maxFigureWidth),
                child: OccupancyBuilder(
                  height: 260,
                  builder: (court, occupancy) => HeatmapDetail(
                    court: court,
                    selections: playerHeatmapSelections(
                      tagId: tagId,
                      name: figure.name,
                      color: figure.color,
                      team: figure.team,
                      occupancy: occupancy,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ThresholdsNote(metrics: figure.metrics),
          ],
        ),
      );
}

/// A player's speed for the whole recording, scrubbable, with the split of
/// that time by intensity and the notes behind both.
class PlayerSpeedScreen extends ConsumerWidget {
  final String tagId;
  final VoidCallback onBackToSessions;

  /// Tall enough that a sprint is a spike rather than a wobble.
  static const double _chartHeight = 320;

  const PlayerSpeedScreen({
    super.key,
    required this.tagId,
    required this.onBackToSessions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlayerFigureScaffold(
        tagId: tagId,
        crumb: 'Speed',
        onBackToSessions: onBackToSessions,
        builder: (context, figure) {
          final window =
              figure.metrics.thresholds.speedWindow.inMilliseconds;
          final zones = figure.metrics.zonesByTag[tagId] ??
              const SpeedZoneBreakdown({});

          return ListView(
            children: [
              SectionTitle(
                title: 'Speed over time',
                description: 'Each point is speed measured over a $window ms '
                    'window, not between consecutive fixes: at UWB sampling '
                    'rates, neighbouring positions are centimetres apart and '
                    'positioning noise would dominate. The dashed line is the '
                    'average over the whole recording, standing time '
                    'included. Tap or drag the chart to move the playhead, '
                    'then return to the court to watch that moment.',
              ),
              const SizedBox(height: 12),
              SpeedChart(
                track: figure.track,
                color: figure.color,
                height: _chartHeight,
              ),
              const SizedBox(height: 16),
              _SpeedStats(track: figure.track),
              const SizedBox(height: 24),
              SectionTitle(
                title: 'Time by intensity',
                description: 'Each measured speed is credited with the time '
                    'since the one before it, so the bands sum to the tracked '
                    'span rather than to a sample count; a gap longer than '
                    '${SpeedZoneBreakdown.maxAttributableGap.inSeconds}s is '
                    'treated as a dropout rather than as time at that speed. '
                    'The bounds are a convention for indoor team sport, not a '
                    'profile of this player — without their own maximum '
                    'speed, any absolute band is.',
              ),
              const SizedBox(height: 10),
              ZoneBreakdownBar(breakdown: zones, color: figure.color),
              const SizedBox(height: 16),
              _ThresholdsNote(metrics: figure.metrics),
            ],
          );
        },
      );
}

/// Everything a figure page needs about the player it is drawn for.
@immutable
class _PlayerFigure {
  final SessionTeamMetrics metrics;
  final PlayerTrackMetrics track;
  final TeamMetrics? team;
  final String name;
  final Color color;

  const _PlayerFigure({
    required this.metrics,
    required this.track,
    required this.team,
    required this.name,
    required this.color,
  });
}

/// The trail, the metrics and the empty cases every player figure page shares.
///
/// Kept in one place so the map page and the speed page cannot disagree about
/// where a reader is or about what a player with no usable samples looks like.
class _PlayerFigureScaffold extends ConsumerWidget {
  final String tagId;

  /// The last breadcrumb: the name of this figure.
  final String crumb;

  final VoidCallback onBackToSessions;
  final Widget Function(BuildContext context, _PlayerFigure figure) builder;

  const _PlayerFigureScaffold({
    required this.tagId,
    required this.crumb,
    required this.onBackToSessions,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session =
        ref.watch(replayControllerProvider.select((s) => s.session));
    final navigator = ref.read(sessionViewProvider.notifier);
    final roster = ref.watch(replayRosterProvider);
    final entry = roster.entryFor(tagId);
    final color = entry?.color ?? TagRoster.unassignedColor;
    final name = entry?.playerName ?? tagId;

    if (session == null) return const SizedBox.shrink();

    final metrics = ref.watch(sessionTeamMetricsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalysisBreadcrumbs(
            crumbs: [
              Breadcrumb('Sessions', onTap: onBackToSessions),
              Breadcrumb(session.name, onTap: navigator.showReplay),
              Breadcrumb('Analysis', onTap: navigator.showTeamAnalysis),
              Breadcrumb(name, onTap: () => navigator.showPlayer(tagId)),
              Breadcrumb(crumb),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: metrics.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Could not compute metrics: $error',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              data: (metrics) {
                final track = _trackFor(metrics);
                if (track == null) {
                  return Center(
                    child: Text(
                      'No usable samples were recorded for this player.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }

                return builder(
                  context,
                  _PlayerFigure(
                    metrics: metrics,
                    track: track,
                    team: metrics.teamOf(tagId),
                    name: name,
                    color: color,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  PlayerTrackMetrics? _trackFor(SessionTeamMetrics metrics) {
    for (final track in metrics.ranked) {
      if (track.tagId == tagId) return track;
    }
    return null;
  }
}

/// The speed figures worth having beside the trace, and no others: distance
/// and its share of the squad belong to the player's page, not to this one.
class _SpeedStats extends ConsumerWidget {
  final PlayerTrackMetrics track;

  const _SpeedStats({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playheadMicros = ref.watch(
      replayControllerProvider.select((s) => s.frame?.timestampMicros),
    );
    final now = playheadMicros == null ? 0.0 : track.speedAt(playheadMicros);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        StatTile(
          label: 'At the playhead',
          value: formatSpeed(now),
          hint: 'Tap the chart to move it',
          emphasised: true,
        ),
        StatTile(
          label: 'Top speed',
          value: formatSpeed(track.maxSpeedMps),
          hint: 'Fastest windowed speed',
        ),
        StatTile(
          label: 'Average speed',
          value: formatSpeed(track.averageSpeedMps),
          hint: 'Standing time included',
        ),
        StatTile(
          label: 'Tracked',
          value: formatElapsed(track.trackedDuration),
          hint: '${track.sampleCount} samples',
        ),
      ],
    );
  }
}

/// What the figures above were computed under, spelled out where there is
/// room for it.
class _ThresholdsNote extends StatelessWidget {
  final SessionTeamMetrics metrics;

  const _ThresholdsNote({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      'Computed under ${metrics.thresholds}. Change them in Settings and '
      'every figure here is recomputed from the stored samples.',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}
