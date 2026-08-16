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

/// One player's movement, in the room the replay side panel does not have.
///
/// Everything here is derived from the same [SessionMetrics] the panel shows,
/// so the two can never disagree; what the page buys is the speed series over
/// time, the split of that time by intensity, and the comparison against the
/// player's own team — none of which is legible in a 300-pixel column.
///
/// This is a summary: the map and the speed trace appear as previews that
/// open their own pages, and the sentences explaining how each figure is
/// arrived at live there rather than here. A page a coach scans between
/// possessions cannot also be the page that documents the method.
class PlayerAnalysisScreen extends ConsumerWidget {
  final String tagId;

  /// Leaves the open session altogether, for the first breadcrumb.
  final VoidCallback onBackToSessions;

  /// Below this width the intensity split and the comparison stack instead of
  /// sitting side by side.
  static const double _wideBreakpoint = 900;

  /// Content width below which the map and the speed chart stack.
  ///
  /// Two figures side by side need enough room that neither is squeezed into
  /// a shape it cannot be read in: the chart loses its time axis to the
  /// 44-pixel speed labels, and the court has a 2:1 aspect it will letterbox
  /// down to nothing to preserve.
  static const double _sideBySideBreakpoint = 720;

  const PlayerAnalysisScreen({
    super.key,
    required this.tagId,
    required this.onBackToSessions,
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
              Breadcrumb(entry?.playerName ?? tagId),
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
              data: (metrics) => _body(context, ref, metrics, entry, color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    SessionTeamMetrics metrics,
    TagRosterEntry? entry,
    Color color,
  ) {
    final theme = Theme.of(context);
    final navigator = ref.read(sessionViewProvider.notifier);

    // The tag can be missing from the metrics when every one of its samples
    // was rejected by the confidence threshold — saying so beats an empty
    // chart.
    final track = _trackFor(metrics);
    if (track == null) {
      return Center(
        child: Text(
          'No usable samples were recorded for this player.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final index = metrics.ranked.indexWhere((t) => t.tagId == tagId);
    final team = metrics.teamOf(tagId);
    final zones = metrics.zonesByTag[tagId] ?? const SpeedZoneBreakdown({});
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final comparison = _TeamComparison(track: track, team: team);
    final intensity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Time by intensity'),
        const SizedBox(height: 8),
        ZoneBreakdownBar(breakdown: zones, color: color),
      ],
    );

    return ListView(
      children: [
        _Header(
          entry: entry,
          track: track,
          color: color,
          teamLabel: team?.label,
          rank: index + 1,
          total: metrics.ranked.length,
          onPrevious: index > 0
              ? () => navigator.showPlayer(metrics.ranked[index - 1].tagId)
              : null,
          onNext: index >= 0 && index < metrics.ranked.length - 1
              ? () => navigator.showPlayer(metrics.ranked[index + 1].tagId)
              : null,
        ),
        const Divider(height: 24),
        _StatTiles(track: track, squad: metrics),
        const SizedBox(height: 20),
        _FigurePreviews(tagId: tagId, track: track, color: color, team: team),
        const SizedBox(height: 20),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: intensity),
              const SizedBox(width: 20),
              SizedBox(width: 320, child: comparison),
            ],
          )
        else ...[
          intensity,
          const SizedBox(height: 20),
          comparison,
        ],
        const SizedBox(height: 16),
        Text(
          'Computed under ${metrics.thresholds}.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  PlayerTrackMetrics? _trackFor(SessionTeamMetrics metrics) {
    for (final track in metrics.ranked) {
      if (track.tagId == tagId) return track;
    }
    return null;
  }
}

/// The map and the speed trace, side by side while the window allows it.
///
/// Both are previews: neither is interactive here, and a tap on either opens
/// the page where it is drawn at a size worth reading and explained.
class _FigurePreviews extends ConsumerWidget {
  final String tagId;
  final PlayerTrackMetrics track;
  final Color color;
  final TeamMetrics? team;

  /// One height for both, so the pair reads as a row rather than as two
  /// panels that happen to be adjacent.
  static const double _height = 200;

  const _FigurePreviews({
    required this.tagId,
    required this.track,
    required this.color,
    required this.team,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = ref.read(sessionViewProvider.notifier);

    final map = _TitledFigure(
      title: 'Where the time was spent',
      child: PlayerHeatmapCard(
        tagId: tagId,
        color: color,
        team: team,
        height: _height,
        onTap: () => navigator.showPlayerHeatmap(tagId),
      ),
    );

    final speed = _TitledFigure(
      title: 'Speed over time',
      child: SpeedChart(
        track: track,
        color: color,
        height: _height,
        onOpen: () => navigator.showPlayerSpeed(tagId),
      ),
    );

    // Measured against the space actually available rather than the window:
    // this block sits inside a page whose padding — and, on a wide window,
    // whose neighbours — decide how much of the width it really gets.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            PlayerAnalysisScreen._sideBySideBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [map, const SizedBox(height: 20), speed],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: map),
            const SizedBox(width: 20),
            Expanded(child: speed),
          ],
        );
      },
    );
  }
}

/// A figure under its heading, with nothing else between the two.
class _TitledFigure extends StatelessWidget {
  final String title;
  final Widget child;

  const _TitledFigure({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title: title),
          const SizedBox(height: 8),
          child,
        ],
      );
}

class _Header extends StatelessWidget {
  final TagRosterEntry? entry;
  final PlayerTrackMetrics track;
  final Color color;
  final String? teamLabel;
  final int rank;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _Header({
    required this.entry,
    required this.track,
    required this.color,
    required this.teamLabel,
    required this.rank,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Everything identifying the player on one ellipsised line, rank
    // included: a separate right-aligned rank would be the first thing to
    // overflow beside the stepper buttons in a phone-width window.
    final subtitle = [
      if (entry != null && entry!.label.isNotEmpty) '#${entry!.label}',
      ?teamLabel,
      track.tagId,
      if (rank > 0) '${ordinal(rank)} of $total by distance',
    ].join(' • ');

    return Row(
      children: [
        PlayerBadge(label: entry?.label ?? '?', color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry?.playerName ?? track.tagId,
                style: theme.textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.keyboard_arrow_up),
          tooltip: 'Previous player',
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: 'Next player',
        ),
      ],
    );
  }
}

class _StatTiles extends ConsumerWidget {
  final PlayerTrackMetrics track;
  final SessionTeamMetrics squad;

  const _StatTiles({required this.track, required this.squad});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playheadMicros = ref.watch(
      replayControllerProvider.select((s) => s.frame?.timestampMicros),
    );
    final now = playheadMicros == null ? 0.0 : track.speedAt(playheadMicros);

    final squadTotal = squad.totalDistanceMeters;
    final share = squadTotal <= 0 ? 0.0 : track.distanceMeters / squadTotal;
    final sprint = (squad.zonesByTag[track.tagId] ?? const SpeedZoneBreakdown({}))
        .inZone(SpeedZone.sprinting);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        StatTile(
          label: 'Distance',
          value: formatMetres(track.distanceMeters),
          hint: '${formatShare(share)} of the squad total',
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
          label: 'At the playhead',
          value: formatSpeed(now),
          hint: 'Scrub to follow it',
          emphasised: true,
        ),
        StatTile(
          label: 'Sprinting',
          value: formatElapsed(sprint),
          hint: '≥ ${SpeedZone.sprinting.lowerBoundMps.toStringAsFixed(1)} m/s',
        ),
        StatTile(
          label: 'Tracked',
          value: formatElapsed(track.trackedDuration),
          hint: '${track.sampleCount} samples',
        ),
        StatTile(
          label: 'Discarded steps',
          value: '${track.discardedSteps}',
          hint: track.discardedSteps == 0
              ? 'No implausible fixes'
              : 'Rejected as positioning noise',
        ),
      ],
    );
  }
}

/// This player against the average of their own team.
///
/// A percentage against a team of one is meaningless, so a team with nobody
/// else in it says so rather than printing 0%.
class _TeamComparison extends StatelessWidget {
  final PlayerTrackMetrics track;
  final TeamMetrics? team;

  const _TeamComparison({required this.track, required this.team});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final team = this.team;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Against ${team?.label ?? 'the squad'}',
          description: team == null || team.playerCount < 2
              ? 'No team-mates were tracked in this session.'
              : 'Compared with the average of '
                  '${team.playerCount} tracked players.',
        ),
        const SizedBox(height: 8),
        if (team != null && team.playerCount >= 2)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _ComparisonRow(
                  label: 'Distance',
                  own: track.distanceMeters,
                  reference: team.averageDistanceMeters,
                  format: formatMetres,
                ),
                _ComparisonRow(
                  label: 'Average speed',
                  own: track.averageSpeedMps,
                  reference: team.averageSpeedMps,
                  format: formatSpeed,
                ),
                _ComparisonRow(
                  label: 'Top speed',
                  own: track.maxSpeedMps,
                  reference: team.maxSpeedMps,
                  referenceLabel: 'team best',
                  format: formatSpeed,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final String label;
  final double own;
  final double reference;
  final String referenceLabel;
  final String Function(double) format;

  const _ComparisonRow({
    required this.label,
    required this.own,
    required this.reference,
    required this.format,
    this.referenceLabel = 'team average',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = reference <= 0 ? 0.0 : (own - reference) / reference;
    final sign = delta >= 0 ? '+' : '−';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  '${format(reference)} $referenceLabel',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                format(own),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '$sign${formatPercent(delta.abs())}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: delta >= 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
