import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/play_metrics.dart';
import '../../analytics/session_metrics.dart';
import '../../analytics/speed_zones.dart';
import '../../analytics/timeline_runs.dart';
import '../../core/duration_format.dart';
import '../../core/metric_format.dart';
import 'analysis_providers.dart';
import 'replay_controller.dart';

/// Heading for one block of an analysis page.
///
/// The description is optional because an overview page is read by scanning:
/// a sentence under every heading is prose to skip past. Pages that show one
/// figure and nothing else — a player's map, their speed trace — are where
/// the explanation belongs, and there it is not optional.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? description;

  const SectionTitle({
    super.key,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = this.description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (description != null)
          Text(
            description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// A figure shown small, opening its own page when tapped.
///
/// One widget for every such preview so the affordance is identical wherever
/// it appears: a reader who learns that the corner glyph means "there is more
/// of this" learns it once.
class OpensInFull extends StatelessWidget {
  /// What opens, for the screen reader and the tooltip.
  final String label;

  final VoidCallback onTap;
  final Widget child;

  const OpensInFull({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: '$label, tap to open',
      child: Tooltip(
        message: 'Open $label',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              child,
              Positioned(
                top: 6,
                right: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One headline figure, sized to be read at a glance rather than squinted at.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final bool emphasised;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 176,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: emphasised ? theme.colorScheme.primary : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A player's shirt number in their team colour, as drawn on the court.
class PlayerBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double size;

  const PlayerBadge({
    super.key,
    required this.label,
    required this.color,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          label,
          style: TextStyle(
            color: const Color(0xFF0C1015),
            fontSize: size * 0.38,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

/// Faint to solid with rising intensity, so a zone bar reads as one scale
/// rather than as five unrelated categories.
Color zoneShade(Color base, SpeedZone zone) => base.withValues(
      alpha: 0.25 + 0.75 * (zone.index / (SpeedZone.values.length - 1)),
    );

/// How tracked time splits across intensity bands.
class ZoneBreakdownBar extends StatelessWidget {
  final SpeedZoneBreakdown breakdown;
  final Color color;

  /// Whether each band's own duration and threshold are spelled out. A team
  /// card wants the shape only; a player's page wants the numbers.
  final bool detailed;

  const ZoneBreakdownBar({
    super.key,
    required this.breakdown,
    required this.color,
    this.detailed = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (breakdown.isEmpty) {
      return Text(
        'Not enough measured time to split by intensity.',
        style: theme.textTheme.bodySmall,
      );
    }

    final present = [
      for (final zone in SpeedZone.values)
        if (breakdown.shareOf(zone) > 0) zone,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: detailed ? 18 : 12,
            child: Row(
              // Stretched, because a bare `ColoredBox` takes the smallest
              // height its constraints allow: under a centred row that is
              // zero, and the bar paints nothing at all.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final zone in present)
                  Expanded(
                    // Thousandths, so a band worth a fraction of a percent
                    // still gets a proportional slice instead of vanishing.
                    flex: math.max(1, (breakdown.shareOf(zone) * 1000).round()),
                    child: ColoredBox(color: zoneShade(color, zone)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: detailed ? 20 : 12,
          runSpacing: 6,
          children: [
            for (final zone in SpeedZone.values)
              if (detailed || breakdown.shareOf(zone) > 0)
                _ZoneLegendItem(
                  zone: zone,
                  color: zoneShade(color, zone),
                  duration: breakdown.inZone(zone),
                  share: breakdown.shareOf(zone),
                  detailed: detailed,
                ),
          ],
        ),
      ],
    );
  }
}

class _ZoneLegendItem extends StatelessWidget {
  final SpeedZone zone;
  final Color color;
  final Duration duration;
  final double share;
  final bool detailed;

  const _ZoneLegendItem({
    required this.zone,
    required this.color,
    required this.duration,
    required this.share,
    required this.detailed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${zone.label} ${formatShare(share)}',
              style: theme.textTheme.bodySmall,
            ),
            if (detailed)
              Text(
                '${formatElapsed(duration)} • '
                '≥ ${zone.lowerBoundMps.toStringAsFixed(1)} m/s',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

/// Chooses the stretch of the recording every figure on the page is measured
/// over.
///
/// Placed at the top of a report rather than on each figure, because the
/// alternative — a per-card toggle — invites reading an attacking distance next
/// to a whole-match average and comparing them. One control means every number
/// on screen always answers the same question.
class PlaySplitSelector extends ConsumerWidget {
  /// Whether attacking and defending could be told apart at all. With no
  /// goalkeeper tracked those two are offered but not selectable, which says
  /// more than hiding them would: the reader learns the feature exists and
  /// what it needs.
  final bool phasesAvailable;

  const PlaySplitSelector({super.key, this.phasesAvailable = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(playSplitProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scaled down rather than scrolled: a control this small should never
        // be something the reader has to find by dragging, and a second
        // scrollable inside a scrolling page is a nuisance to drive with a
        // trackpad and with a test alike.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SegmentedButton<PlaySplit>(
            showSelectedIcon: false,
            segments: [
              for (final split in PlaySplit.selectable)
                ButtonSegment(
                  value: split,
                  label: Text(split.label),
                  enabled: phasesAvailable || split == PlaySplit.onCourt,
                ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) =>
                ref.read(playSplitProvider.notifier).select(selection.first),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          phasesAvailable
              ? selected.description
              : 'Bench time excluded. Attacking and defending need a '
                  'goalkeeper on the roster to be told apart.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The colour black, for bench time on a [PlayTimeline].
///
/// Named rather than inlined because it means something: every other band on
/// a timeline is a shade of the team's own colour, and the one state that is
/// *not* play reads as an absence of it.
const Color kBenchColor = Color(0xFF000000);

/// Two readings of one team's colour, for the two phases of play.
///
/// Attacking keeps the colour the team is drawn in on the court, so a band is
/// recognisably theirs at a glance; defending is the same hue taken deeper and
/// muted. Deliberately a variation rather than a second colour: which team a
/// band belongs to and what they were doing are different questions, and only
/// the second one should need the legend.
///
/// Deeper rather than paler, which was the first attempt and was wrong. The
/// team palette is already light — every colour in it sits near 0.7 lightness
/// so it carries on a dark court — so lightening washed defending out to
/// something indistinguishable from the unpainted ground behind the bar. The
/// lightness floor keeps it from closing on the black used for bench time from
/// the other direction, so all three bands stay apart whatever colour a team
/// picked.
({Color attacking, Color defending}) phaseShades(Color teamColor) {
  final hsl = HSLColor.fromColor(teamColor);
  return (
    attacking: teamColor,
    defending: hsl
        .withSaturation((hsl.saturation * 0.55).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.55).clamp(0.30, 0.62))
        .toColor(),
  );
}

/// One state a [PlayTimeline] paints, and every stretch of time it held for.
@immutable
class TimelineBand {
  final String label;
  final Color color;

  /// Half-open `(start, end)` ranges in absolute microseconds.
  final List<(int, int)> spans;

  const TimelineBand({
    required this.label,
    required this.color,
    required this.spans,
  });

  TimelineBand.fromRuns({
    required this.label,
    required this.color,
    required Iterable<TimedRun<Object?>> runs,
  }) : spans = [for (final run in runs) (run.startMicros, run.endMicros)];

  Duration get total => Duration(
        microseconds: spans.fold(0, (sum, span) => sum + (span.$2 - span.$1)),
      );

  bool get isEmpty => spans.isEmpty;
}

/// What happened, in the order it happened, along a real time axis.
///
/// This replaces the stacked percentage bar it grew out of, because the two
/// answer different questions and only one of them was being asked. A bar
/// saying "40% defending, 35% attacking, 25% bench" is equally true of a
/// player who was substituted once and of one who was rotated every two
/// minutes, and of a side that defended one long spell and one that traded
/// possession twenty times. The sequence is the part a coach recognises the
/// match from, and the totals underneath lose nothing by sitting below it.
///
/// Time nothing is known about — before a tag started reporting, after it
/// stopped — is left as bare ground rather than stretched over, so the bar
/// never implies coverage it does not have.
class PlayTimeline extends StatelessWidget {
  final List<TimelineBand> bands;

  /// The instant the axis starts, and how long it runs for. Passing the
  /// session's own origin to every timeline is what lets two of them be read
  /// one above the other.
  final int startMicros;
  final Duration duration;

  final double height;

  /// What the legend's percentages are measured against, in words.
  final String referenceLabel;

  const PlayTimeline({
    super.key,
    required this.bands,
    required this.startMicros,
    required this.duration,
    this.height = 26,
    this.referenceLabel = 'of the session',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spanMicros = duration.inMicroseconds;

    if (spanMicros <= 0) {
      return Text('No time was measured.', style: theme.textTheme.bodySmall);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            size: Size(double.infinity, height),
            painter: _TimelinePainter(
              bands: bands,
              startMicros: startMicros,
              spanMicros: spanMicros,
              ground: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // The axis, named at both ends. Without it the bar is a proportion
        // again rather than a clock.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatElapsed(Duration.zero),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Text(
              formatElapsed(duration),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            for (final band in bands)
              _TimelineLegendItem(
                band: band,
                share: band.total.inMicroseconds / spanMicros,
                referenceLabel: referenceLabel,
              ),
          ],
        ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<TimelineBand> bands;
  final int startMicros;
  final int spanMicros;
  final Color ground;

  /// Narrowest a stretch may be drawn, in logical pixels.
  ///
  /// A six-second possession in an hour-long match is a third of a pixel wide
  /// and would disappear entirely. Widening it distorts the proportions very
  /// slightly, which the totals underneath are there to correct; dropping it
  /// would hide an event, which nothing corrects.
  static const double _minWidth = 1.5;

  const _TimelinePainter({
    required this.bands,
    required this.startMicros,
    required this.spanMicros,
    required this.ground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);

    final scale = size.width / spanMicros;
    final paint = Paint();

    for (final band in bands) {
      paint.color = band.color;
      for (final (start, end) in band.spans) {
        final left = (start - startMicros) * scale;
        final width = math.max((end - start) * scale, _minWidth);
        if (left + width < 0 || left > size.width) continue;
        canvas.drawRect(
          Rect.fromLTWH(left, 0, width, size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.bands != bands ||
      old.startMicros != startMicros ||
      old.spanMicros != spanMicros ||
      old.ground != ground;
}

class _TimelineLegendItem extends StatelessWidget {
  final TimelineBand band;
  final double share;
  final String referenceLabel;

  const _TimelineLegendItem({
    required this.band,
    required this.share,
    required this.referenceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: band.color,
            shape: BoxShape.circle,
            // Black on a dark surface needs an edge to read as a filled dot
            // rather than as a hole.
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(band.label, style: theme.textTheme.bodySmall),
            Text(
              '${formatElapsed(band.total)} • '
              '${formatShare(share)} $referenceLabel',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A player's windowed speed for the whole recording, with the playhead on it
/// — the view that turns "top speed 7.4 m/s" into "that sprint, there".
class SpeedChart extends ConsumerWidget {
  final PlayerTrackMetrics track;
  final Color color;
  final double height;

  /// When set, the chart is a preview: a tap opens the page named by
  /// [openLabel] instead of moving the playhead.
  ///
  /// The two cannot coexist on one chart — a tap either seeks or navigates —
  /// and seeking is the interaction that needs the room, so it is the full
  /// page that keeps it.
  final VoidCallback? onOpen;

  final String openLabel;

  const SpeedChart({
    super.key,
    required this.track,
    required this.color,
    this.height = 220,
    this.onOpen,
    this.openLabel = 'the speed chart',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (track.speeds.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Too few samples to measure speed over time.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    final playheadMicros = ref.watch(
      replayControllerProvider.select((s) => s.frame?.timestampMicros),
    );
    // Seeking needs the recording's zero to turn an x position back into a
    // transport position; without a frame on screen the chart is read-only.
    final startMicros = ref.watch(
      replayControllerProvider.select((s) => s.recordingStartMicros),
    );
    final controller = ref.read(replayControllerProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        final geometry = _ChartGeometry(track: track, size: size);

        void seekTo(Offset local) {
          if (startMicros == null) return;
          controller.seek(
            Duration(microseconds: geometry.microsAt(local.dx) - startMicros),
          );
        }

        final chart = CustomPaint(
          size: size,
          painter: _SpeedChartPainter(
            geometry: geometry,
            color: color,
            gridColor: theme.colorScheme.outlineVariant,
            surfaceColor: theme.colorScheme.surfaceContainerHighest,
            labelColor: theme.colorScheme.onSurfaceVariant,
            playheadColor: theme.colorScheme.onSurface,
            playheadMicros: playheadMicros,
          ),
        );

        final onOpen = this.onOpen;
        if (onOpen != null) {
          return OpensInFull(label: openLabel, onTap: onOpen, child: chart);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition),
          onHorizontalDragUpdate: (details) => seekTo(details.localPosition),
          child: chart,
        );
      },
    );
  }
}

/// Maps between the speed series and chart pixels, in both directions.
class _ChartGeometry {
  final PlayerTrackMetrics track;
  final Size size;

  final int startMicros;
  final int endMicros;
  final double maxSpeed;

  static const double _padLeft = 44;
  static const double _padRight = 8;
  static const double _padTop = 10;
  static const double _padBottom = 22;

  _ChartGeometry({required this.track, required this.size})
      : startMicros = track.speedTimesMicros.first,
        endMicros = track.speedTimesMicros.last,
        // Headroom above the peak so the fastest moment is a visible spike
        // rather than a line pinned to the top edge. The floor keeps a walk
        // from being drawn as if it filled the axis.
        maxSpeed = math.max(1.0, track.maxSpeedMps * 1.15);

  double get left => _padLeft;
  double get right => size.width - _padRight;
  double get top => _padTop;
  double get bottom => size.height - _padBottom;
  double get plotWidth => math.max(1.0, right - left);
  double get plotHeight => math.max(1.0, bottom - top);

  double xAt(int micros) {
    final span = endMicros - startMicros;
    if (span <= 0) return left;
    final fraction = ((micros - startMicros) / span).clamp(0.0, 1.0);
    return left + fraction * plotWidth;
  }

  double yAt(double speed) =>
      bottom - (speed / maxSpeed).clamp(0.0, 1.0) * plotHeight;

  int microsAt(double x) {
    final fraction = ((x - left) / plotWidth).clamp(0.0, 1.0);
    return startMicros + (fraction * (endMicros - startMicros)).round();
  }
}

class _SpeedChartPainter extends CustomPainter {
  final _ChartGeometry geometry;
  final Color color;
  final Color gridColor;
  final Color surfaceColor;
  final Color labelColor;
  final Color playheadColor;
  final int? playheadMicros;

  _SpeedChartPainter({
    required this.geometry,
    required this.color,
    required this.gridColor,
    required this.surfaceColor,
    required this.labelColor,
    required this.playheadColor,
    required this.playheadMicros,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final track = geometry.track;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
            geometry.left, geometry.top, geometry.right, geometry.bottom),
        const Radius.circular(8),
      ),
      Paint()..color = surfaceColor,
    );

    _paintGrid(canvas);

    // One point per pixel column, taking the fastest speed in each. Peaks
    // survive decimation — a chart that hid the sprint it is drawn to show
    // would be worse than no chart — at the cost of reading a little high
    // where a column spans many samples.
    final columns = <int, double>{};
    for (var i = 0; i < track.speeds.length; i++) {
      final column = geometry.xAt(track.speedTimesMicros[i]).round();
      final speed = track.speeds[i];
      if (speed > (columns[column] ?? -1)) columns[column] = speed;
    }

    final xs = columns.keys.toList()..sort();
    final line = Path();
    for (var i = 0; i < xs.length; i++) {
      final point = Offset(xs[i].toDouble(), geometry.yAt(columns[xs[i]]!));
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }

    final area = Path.from(line)
      ..lineTo(xs.last.toDouble(), geometry.bottom)
      ..lineTo(xs.first.toDouble(), geometry.bottom)
      ..close();

    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    _paintAverage(canvas);
    _paintPlayhead(canvas);
  }

  void _paintGrid(Canvas canvas) {
    final paint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (final fraction in const [0.0, 0.5, 1.0]) {
      final speed = geometry.maxSpeed * fraction;
      final y = geometry.yAt(speed);
      canvas.drawLine(
          Offset(geometry.left, y), Offset(geometry.right, y), paint);
      _paintText(
        canvas,
        speed.toStringAsFixed(1),
        Offset(geometry.left - 6, y),
        anchorRight: true,
      );
    }

    _paintText(
      canvas,
      'm/s',
      Offset(geometry.left - 6, geometry.top - 2),
      anchorRight: true,
    );

    final span =
        Duration(microseconds: geometry.endMicros - geometry.startMicros);
    _paintText(
      canvas,
      '00:00',
      Offset(geometry.left, geometry.bottom + 4),
      topAligned: true,
    );
    _paintText(
      canvas,
      formatElapsed(span),
      Offset(geometry.right, geometry.bottom + 4),
      anchorRight: true,
      topAligned: true,
    );
  }

  void _paintAverage(Canvas canvas) {
    final y = geometry.yAt(geometry.track.averageSpeedMps);
    final paint = Paint()
      ..color = labelColor.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    // Dashed by hand: the average is a reference, and a solid line at the
    // same weight as the trace would read as a second measurement.
    for (var x = geometry.left; x < geometry.right; x += 8) {
      canvas.drawLine(
          Offset(x, y), Offset(math.min(x + 4, geometry.right), y), paint);
    }
  }

  void _paintPlayhead(Canvas canvas) {
    final micros = playheadMicros;
    if (micros == null) return;
    if (micros < geometry.startMicros || micros > geometry.endMicros) return;

    final x = geometry.xAt(micros);
    canvas.drawLine(
      Offset(x, geometry.top),
      Offset(x, geometry.bottom),
      Paint()
        ..color = playheadColor.withValues(alpha: 0.85)
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(
      Offset(x, geometry.yAt(geometry.track.speedAt(micros))),
      4,
      Paint()..color = playheadColor,
    );
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset at, {
    bool anchorRight = false,
    bool topAligned = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      Offset(
        anchorRight ? at.dx - painter.width : at.dx,
        topAligned ? at.dy : at.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_SpeedChartPainter old) =>
      old.playheadMicros != playheadMicros ||
      old.geometry.track != geometry.track ||
      old.geometry.size != geometry.size ||
      old.color != color;
}

String ordinal(int value) {
  if (value % 100 >= 11 && value % 100 <= 13) return '${value}th';
  return switch (value % 10) {
    1 => '${value}st',
    2 => '${value}nd',
    3 => '${value}rd',
    _ => '${value}th',
  };
}
