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
            child: metrics.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Could not compute metrics: $error',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              data: (metrics) => metrics.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing was recorded for this session.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : _Report(metrics: metrics),
            ),
          ),
        ],
      ),
    );
  }
}

class _Report extends ConsumerWidget {
  final SessionTeamMetrics metrics;

  /// Below this width the team cards stack instead of sitting side by side.
  static const double _wideBreakpoint = 820;

  const _Report({required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roster = ref.watch(replayRosterProvider);
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final fastest = metrics.fastest;
    final sprinting = metrics.timeIn(SpeedZone.sprinting);

    final cards = [
      for (final team in metrics.teams)
        _TeamCard(team: team, color: _colorFor(team, roster)),
    ];

    return ListView(
      children: [
        const SectionTitle(
          title: 'Session totals',
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
              label: 'Fastest moment',
              value: formatSpeed(fastest?.maxSpeedMps ?? 0),
              hint: fastest == null
                  ? 'No speeds measured'
                  : roster.entryFor(fastest.tagId)?.playerName ??
                      fastest.tagId,
              emphasised: true,
            ),
            StatTile(
              label: 'Time on court',
              value: formatElapsed(metrics.trackedDuration),
              hint: 'Longest tracked player',
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
        _PlayerTable(metrics: metrics, roster: roster),
        const SizedBox(height: 16),
        Text(
          'Computed under ${metrics.thresholds}.',
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

class _TeamCard extends StatelessWidget {
  final TeamMetrics team;
  final Color color;

  const _TeamCard({required this.team, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fastest = team.fastest;

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
                  label: 'Top speed',
                  value: formatSpeed(team.maxSpeedMps),
                  hint: fastest == null ? '—' : 'Best on this side',
                ),
                StatTile(
                  label: 'Average speed',
                  value: formatSpeed(team.averageSpeedMps),
                  hint: 'Mean of the players',
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
class _PlayerTable extends ConsumerWidget {
  final SessionTeamMetrics metrics;
  final TagRoster roster;

  const _PlayerTable({required this.metrics, required this.roster});

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
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Player')),
          DataColumn(label: Text('Team')),
          DataColumn(label: Text('Distance'), numeric: true),
          DataColumn(label: Text('Top'), numeric: true),
          DataColumn(label: Text('Avg'), numeric: true),
          DataColumn(label: Text('Sprinting'), numeric: true),
          DataColumn(label: Text('Tracked'), numeric: true),
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
    final sprint = (metrics.zonesByTag[track.tagId] ??
            const SpeedZoneBreakdown({}))
        .inZone(SpeedZone.sprinting);

    Widget number(String text) => Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
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
        DataCell(number(formatMetres(track.distanceMeters))),
        DataCell(number(formatSpeed(track.maxSpeedMps))),
        DataCell(number(formatSpeed(track.averageSpeedMps))),
        DataCell(number(formatElapsed(sprint))),
        DataCell(number(formatElapsed(track.trackedDuration))),
      ],
    );
  }
}
