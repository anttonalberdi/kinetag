import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/play_metrics.dart';
import '../../analytics/possession.dart';
import '../../analytics/session_metrics.dart';
import '../../analytics/speed_zones.dart';
import '../../analytics/team_metrics.dart';
import '../../core/duration_format.dart';
import '../../core/metric_format.dart';
import '../../domain/domain.dart';
import '../court/tag_roster.dart';
import 'analysis_navigation.dart';
import 'analysis_providers.dart';
import 'analysis_widgets.dart';
import 'heatmap_panel.dart';
import 'replay_controller.dart';
import 'replay_screen.dart';

/// Team-wide analysis of the open session: the totals, each side's share of
/// them, and the ranking every player's own page is reached from.
///
/// The session's own roster snapshot decides who is on which team, so a
/// recording is always split the way it was captured — renaming a team in
/// setup months later cannot rewrite a stored session's report.
class SessionAnalysisScreen extends ConsumerWidget {
  /// Leaves the open session altogether, for the first breadcrumb.
  final VoidCallback onBackToSessions;

  const SessionAnalysisScreen({super.key, required this.onBackToSessions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session =
        ref.watch(replayControllerProvider.select((s) => s.session));
    final navigator = ref.read(sessionViewProvider.notifier);

    if (session == null) return const SizedBox.shrink();

    final play = ref.watch(sessionPlayMetricsProvider);
    final teams = ref.watch(splitTeamMetricsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalysisBreadcrumbs(
            crumbs: [
              Breadcrumb('Sessions', onTap: onBackToSessions),
              Breadcrumb(session.name, onTap: navigator.showReplay),
              const Breadcrumb('Analysis'),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  session.name,
                  style: theme.textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: navigator.showReplay,
                icon: const Icon(Icons.sports_handball, size: 18),
                label: const Text('Back to the court'),
              ),
            ],
          ),
          Text(
            [
              session.status.displayName,
              if (session.duration != null) formatElapsed(session.duration!),
              '${session.sampleCount} samples',
              '${session.receivers.length} receivers',
            ].join(' • '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Divider(height: 24),
          Expanded(
            child: play.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Could not compute metrics: $error',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              data: (play) {
                final metrics = teams.value;
                if (play.isEmpty || metrics == null || metrics.isEmpty) {
                  return Center(
                    child: Text(
                      'Nothing was recorded for this session.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }
                return _Report(metrics: metrics, play: play);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Report extends ConsumerWidget {
  final SessionTeamMetrics metrics;
  final SessionPlayMetrics play;

  /// Below this width the team cards stack instead of sitting side by side.
  static const double _wideBreakpoint = 820;

  const _Report({required this.metrics, required this.play});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roster = ref.watch(replayRosterProvider);
    final split = ref.watch(playSplitProvider);
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final fastest = metrics.fastest;
    final sprinting = metrics.timeIn(SpeedZone.sprinting);

    final cards = [
      for (final team in metrics.teams)
        _TeamCard(
          team: team,
          color: _colorFor(team, roster),
          play: play,
          split: split,
        ),
    ];

    return ListView(
      children: [
        _GameTime(play: play, roster: roster, metrics: metrics),
        const SizedBox(height: 24),
        const SectionTitle(
          title: 'What is being measured',
          description: 'Every figure below is measured over the stretch '
              'chosen here, and nothing else.',
        ),
        const SizedBox(height: 10),
        PlaySplitSelector(phasesAvailable: play.hasPhases),
        const SizedBox(height: 24),
        SectionTitle(
          title: 'Totals — ${split.label.toLowerCase()}',
          description: 'Every tracked player added together.',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatTile(
              label: 'Players tracked',
              value: '${metrics.playerCount}',
              hint: '${metrics.teams.length} '
                  '${metrics.teams.length == 1 ? 'group' : 'groups'}',
            ),
            StatTile(
              label: 'Total distance',
              value: formatMetres(metrics.totalDistanceMeters),
              hint: '${formatMetres(metrics.averageDistanceMeters)} per player',
            ),
            StatTile(
              label: 'Work rate',
              value: formatMetresPerMinute(metrics.metresPerMinute),
              hint: 'Per minute measured',
            ),
            StatTile(
              label: 'Fastest moment',
              value: formatSpeed(fastest?.maxSpeedMps ?? 0),
              hint: fastest == null
                  ? 'No speeds measured'
                  : roster.entryFor(fastest.tagId)?.playerName ??
                      fastest.tagId,
              emphasised: true,
            ),
            StatTile(
              label: 'Measured',
              value: formatElapsed(metrics.measuredDuration),
              hint: 'Player-time combined',
            ),
            StatTile(
              label: 'Sprinting',
              value: formatElapsed(sprinting),
              hint: 'Player-time combined',
            ),
          ],
        ),
        const SizedBox(height: 24),
        SectionTitle(
          title: metrics.teams.length > 1 ? 'By team' : 'Squad',
          description: 'Totals are the sum of a side; averages are per '
              'tracked player, so sides of different sizes stay comparable.',
        ),
        const SizedBox(height: 10),
        if (isWide && cards.length > 1)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          )
        else
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card,
            ),
        const SizedBox(height: 24),
        const SectionTitle(
          title: 'Players',
          description: 'Ranked by distance. Select anyone for their own page.',
        ),
        const SizedBox(height: 10),
        _PlayerTable(
          metrics: metrics,
          play: play,
          split: split,
          roster: roster,
        ),
        const SizedBox(height: 16),
        Text(
          'Computed under ${metrics.thresholds} '
          'and ${play.playThresholds}.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// A team takes the colour its players are drawn in on the court, read from
  /// the roster rather than from the team record, so that a session recorded
  /// before teams carried a colour still matches what the replay shows.
  static Color _colorFor(TeamMetrics team, TagRoster roster) {
    for (final track in team.tracks) {
      final entry = roster.entryFor(track.tagId);
      if (entry != null) return entry.color;
    }
    return TagRoster.unassignedColor;
  }
}

/// How long the session ran, how much of it was played, and how it divided
/// between the two ends.
///
/// Deliberately above the split selector and outside its scope: these are the
/// facts the rest of the report is measured *against*, and showing them inside
/// a split would invite reading "18:20 attacking" as the length of the match.
class _GameTime extends StatelessWidget {
  final SessionPlayMetrics play;
  final TagRoster roster;
  final SessionTeamMetrics metrics;

  const _GameTime({
    required this.play,
    required this.roster,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tracked = play.totalPlayingTime + play.totalBenchTime;
    final benchShare = tracked.inMicroseconds <= 0
        ? 0.0
        : play.totalBenchTime.inMicroseconds / tracked.inMicroseconds;

    // One per time a player came on after the first — which is what a coach
    // counts as a substitution, and is not the same as the number of stints.
    final substitutions = play.byTagId.values.fold<int>(
      0,
      (sum, player) =>
          sum + (player.stintCount > 1 ? player.stintCount - 1 : 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Game time',
          description: 'Read off the tags: a player inside the lines is '
              'playing, one beyond them is not.',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatTile(
              label: 'Session length',
              value: formatElapsed(play.sessionDuration),
              hint: 'Start to stop',
              emphasised: true,
            ),
            StatTile(
              label: 'Playing time',
              value: formatElapsed(play.totalPlayingTime),
              hint: 'Player-time on court',
            ),
            StatTile(
              label: 'Bench time',
              value: formatElapsed(play.totalBenchTime),
              hint: play.hasBenchTime
                  ? '${formatShare(benchShare)} of tracked time'
                  : 'Nobody left the court',
            ),
            StatTile(
              label: 'Substitutions',
              value: '$substitutions',
              hint: 'Times a player came on',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'HOW THE MATCH DIVIDED',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        if (!play.hasPhases)
          Text(
            'Attacking and defending could not be told apart: it is read from '
            'how far each goalkeeper stands off their own line, and this '
            'session has no tracked goalkeeper to read.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          TimeBreakdownBar(
            total: play.possession.measuredDuration,
            parts: [
              for (final side in TeamSide.values)
                TimeShare(
                  label: '${_labelFor(side)} attacking',
                  duration:
                      play.possession.teamTimeIn(side, PlayPhase.attacking),
                  color: _colorForSide(side),
                ),
              TimeShare(
                label: 'Unclear',
                duration:
                    play.possession.teamTimeIn(TeamSide.home, PlayPhase.unclear),
                color: theme.colorScheme.outlineVariant,
              ),
            ],
          ),
      ],
    );
  }

  String _labelFor(TeamSide side) {
    for (final team in metrics.teams) {
      if (team.side == side) return team.label;
    }
    return side.displayName;
  }

  Color _colorForSide(TeamSide side) {
    for (final team in metrics.teams) {
      if (team.side == side) return _Report._colorFor(team, roster);
    }
    return TagRoster.unassignedColor;
  }
}

class _TeamCard extends StatelessWidget {
  final TeamMetrics team;
  final Color color;
  final SessionPlayMetrics play;
  final PlaySplit split;

  const _TeamCard({
    required this.team,
    required this.color,
    required this.play,
    required this.split,
  });

  Duration _attacking(TeamSide side) =>
      play.possession.teamTimeIn(side, PlayPhase.attacking);

  double _attackingShare(TeamSide side) {
    final total = play.possession.measuredDuration.inMicroseconds;
    return total <= 0 ? 0 : _attacking(side).inMicroseconds / total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fastest = team.fastest;
    final side = team.side;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    team.label,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${team.playerCount} '
                  '${team.playerCount == 1 ? 'player' : 'players'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                StatTile(
                  label: 'Distance',
                  value: formatMetres(team.totalDistanceMeters),
                  hint: '${formatMetres(team.averageDistanceMeters)} '
                      'per player',
                ),
                StatTile(
                  label: 'Work rate',
                  value: formatMetresPerMinute(team.metresPerMinute),
                  hint: 'Per minute measured',
                ),
                StatTile(
                  label: 'Top speed',
                  value: formatSpeed(team.maxSpeedMps),
                  hint: fastest == null ? '—' : 'Best on this side',
                ),
                // Average speed is deliberately absent: it is the work rate
                // divided by sixty, and two tiles carrying one fact is how a
                // card stops being scannable.
                StatTile(
                  label: split.label,
                  value: formatElapsed(team.averageDuration),
                  hint: 'Per player',
                ),
                if (side != null && play.hasPhases)
                  StatTile(
                    label: 'Attacking',
                    value: formatElapsed(_attacking(side)),
                    hint: '${formatShare(_attackingShare(side))} of the match',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ZoneBreakdownBar(
              breakdown: team.zones,
              color: color,
              detailed: false,
            ),
            const SizedBox(height: 14),
            Text(
              'WHERE THE TIME WAS SPENT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            TeamHeatmapCard(team: team, color: color),
          ],
        ),
      ),
    );
  }
}

/// Every tracked player, ranked, with the columns a coach scans down.
///
/// Horizontally scrollable rather than responsive: dropping columns on a
/// narrow window would silently change which figures a phone user can see.
/// Every tracked player, ranked, with the columns a coach scans down.
///
/// The time columns carry the split's duration twice over — as a clock reading
/// and as a share of the session — because a coach needs both to act on it: a
/// bare "12:40" says nothing without knowing the match was twenty minutes, and
/// a bare "63%" says nothing about whether that was a long shift or a short
/// one.
class _PlayerTable extends ConsumerWidget {
  final SessionTeamMetrics metrics;
  final SessionPlayMetrics play;
  final PlaySplit split;
  final TagRoster roster;

  const _PlayerTable({
    required this.metrics,
    required this.play,
    required this.split,
    required this.roster,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final navigator = ref.read(sessionViewProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 52,
        columnSpacing: 20,
        columns: [
          const DataColumn(label: Text('#')),
          const DataColumn(label: Text('Player')),
          const DataColumn(label: Text('Team')),
          DataColumn(label: Text(split.label), numeric: true),
          const DataColumn(label: Text('Of session'), numeric: true),
          const DataColumn(label: Text('Distance'), numeric: true),
          const DataColumn(label: Text('Work rate'), numeric: true),
          const DataColumn(label: Text('Top'), numeric: true),
          const DataColumn(label: Text('Avg'), numeric: true),
          const DataColumn(label: Text('Sprinting'), numeric: true),
        ],
        rows: [
          for (var i = 0; i < metrics.ranked.length; i++)
            _row(context, theme, navigator, i, metrics.ranked[i]),
        ],
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    ThemeData theme,
    SessionViewNavigator navigator,
    int index,
    PlayerTrackMetrics track,
  ) {
    final entry = roster.entryFor(track.tagId);
    final team = metrics.teamOf(track.tagId);
    final player = play.forTag(track.tagId);
    final sprint = (metrics.zonesByTag[track.tagId] ??
            const SpeedZoneBreakdown({}))
        .inZone(SpeedZone.sprinting);

    final measured = player?.durationOf(split) ?? track.trackedDuration;
    final sessionMicros = play.sessionDuration.inMicroseconds;
    final share =
        sessionMicros <= 0 ? 0.0 : measured.inMicroseconds / sessionMicros;

    final minutes = measured.inMicroseconds / 6e7;
    final rate = minutes <= 0 ? 0.0 : track.distanceMeters / minutes;

    Widget number(String text, {bool muted = false}) => Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: muted ? theme.colorScheme.onSurfaceVariant : null,
          ),
        );

    return DataRow(
      onSelectChanged: (_) => navigator.showPlayer(track.tagId),
      cells: [
        DataCell(Text('${index + 1}')),
        DataCell(
          Row(
            children: [
              PlayerBadge(
                label: entry?.label ?? '?',
                color: entry?.color ?? TagRoster.unassignedColor,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(entry?.playerName ?? track.tagId),
            ],
          ),
        ),
        DataCell(Text(team?.label ?? SessionTeamMetrics.unassignedLabel)),
        DataCell(number(formatElapsed(measured))),
        DataCell(number(formatShare(share), muted: true)),
        DataCell(number(formatMetres(track.distanceMeters))),
        DataCell(number(formatMetresPerMinute(rate))),
        DataCell(number(formatSpeed(track.maxSpeedMps))),
        DataCell(number(formatSpeed(track.averageSpeedMps))),
        DataCell(number(formatElapsed(sprint))),
      ],
    );
  }
}
