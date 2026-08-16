import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/session_metrics.dart';
import '../../analytics/speed_zones.dart';
import '../../core/duration_format.dart';
import '../../core/metric_format.dart';
import 'replay_controller.dart';

/// Heading for one block of an analysis page.
class SectionTitle extends StatelessWidget {
  final String title;
  final String description;

  const SectionTitle({
    super.key,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        Text(
          description,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
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

/// A player's windowed speed for the whole recording, with the playhead on it
/// — the view that turns "top speed 7.4 m/s" into "that sprint, there".
class SpeedChart extends ConsumerWidget {
  final PlayerTrackMetrics track;
  final Color color;
  final double height;

  const SpeedChart({
    super.key,
    required this.track,
    required this.color,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (track.speeds.isEmpty) {
      return SizedBox(
        height: 80,
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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition),
          onHorizontalDragUpdate: (details) => seekTo(details.localPosition),
          child: CustomPaint(
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
          ),
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
