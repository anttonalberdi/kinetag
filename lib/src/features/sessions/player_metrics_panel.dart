import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics_providers.dart';
import '../../analytics/session_metrics.dart';
import '../court/tag_roster.dart';
import 'replay_controller.dart';
import 'replay_screen.dart';

/// Per-player movement metrics for the session being replayed.
///
/// Distance, maximum and average speed come from the whole recording;
/// "now" is the speed in force at the playhead, so scrubbing to a sprint
/// shows the sprint. Everything is derived from the stored samples on
/// demand — nothing here is a stored figure that could go stale.
class PlayerMetricsPanel extends ConsumerWidget {
  const PlayerMetricsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session =
        ref.watch(replayControllerProvider.select((s) => s.session));

    if (session == null) return const SizedBox.shrink();

    final metrics = ref.watch(sessionMetricsProvider(session.id));
    final roster = ref.watch(replayRosterProvider);
    final playheadMicros = ref.watch(
      replayControllerProvider.select((s) => s.frame?.timestampMicros),
    );

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Movement', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Distance • max / avg / now speed',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 20),
            Expanded(
              child: metrics.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text(
                  'Could not compute metrics: $error',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                data: (metrics) => metrics.isEmpty
                    ? Text(
                        'Nothing was recorded for this session.',
                        style: theme.textTheme.bodySmall,
                      )
                    : ListView(
                        children: [
                          for (final track in metrics.byDistance)
                            _MetricRow(
                              entry: roster.entryFor(track.tagId),
                              track: track,
                              playheadMicros: playheadMicros,
                            ),
                          const SizedBox(height: 8),
                          _TotalRow(metrics: metrics),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final TagRosterEntry? entry;
  final PlayerTrackMetrics track;
  final int? playheadMicros;

  const _MetricRow({
    required this.entry,
    required this.track,
    required this.playheadMicros,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now =
        playheadMicros == null ? 0.0 : track.speedAt(playheadMicros!);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4, right: 8),
            decoration: BoxDecoration(
              color: entry?.color ?? TagRoster.unassignedColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry?.playerName ?? track.tagId,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_metres(track.distanceMeters)} • '
                  '${_speed(track.maxSpeedMps)} / '
                  '${_speed(track.averageSpeedMps)} / '
                  '${_speed(now)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final SessionMetrics metrics;

  const _TotalRow({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Squad total', style: theme.textTheme.bodySmall),
        Text(
          _metres(metrics.totalDistanceMeters),
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Metres up to a kilometre, then kilometres — a squad total passes 1 km
/// within a few minutes and reads badly as five digits.
String _metres(double metres) => metres >= 1000
    ? '${(metres / 1000).toStringAsFixed(2)} km'
    : '${metres.toStringAsFixed(1)} m';

String _speed(double metresPerSecond) =>
    '${metresPerSecond.toStringAsFixed(1)} m/s';
