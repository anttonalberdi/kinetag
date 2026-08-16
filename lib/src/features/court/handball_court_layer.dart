import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;

import '../../core/court_view_transform.dart';
import '../../domain/court.dart';
import 'court_layer.dart';
import 'court_theme.dart';
import 'handball_court_geometry.dart';

/// Draws the handball playing surface and its regulation markings.
///
/// The geometry is built once in world metres (see [HandballCourtGeometry])
/// and transformed to screen space with a single matrix per paint. This keeps
/// every marking exactly proportional under resize and avoids rebuilding
/// arcs each frame.
class HandballCourtLayer extends CourtLayer {
  final Court court;
  final CourtTheme theme;

  HandballCourtLayer({
    required this.court,
    this.theme = const CourtTheme(),
  }) : _geometry = HandballCourtGeometry(court);

  final HandballCourtGeometry _geometry;

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    // World metres -> screen pixels, as a single affine transform.
    final matrix = _worldToScreenMatrix(transform);

    final strokeWidth = theme.strokeWidth(transform.scale);
    final linePaint = Paint()
      ..color = theme.lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    final courtRectOnScreen = transform.worldRectToScreen(_geometry.bounds);

    _paintSurface(canvas, courtRectOnScreen, matrix);
    _paintGoalAreas(canvas, matrix);

    // Markings.
    canvas.drawPath(_geometry.boundary.transform(matrix), linePaint);
    canvas.drawPath(_geometry.centreLine.transform(matrix), linePaint);

    for (final path in _geometry.goalAreaLines) {
      canvas.drawPath(path.transform(matrix), linePaint);
    }
    for (final path in _geometry.sevenMetreLines) {
      canvas.drawPath(path.transform(matrix), linePaint);
    }
    for (final path in _geometry.goalkeeperLines) {
      canvas.drawPath(path.transform(matrix), linePaint);
    }

    _paintFreeThrowLines(canvas, matrix, courtRectOnScreen, linePaint);
    _paintGoals(canvas, matrix, strokeWidth);
  }

  void _paintSurface(Canvas canvas, Rect courtRect, Float64List matrix) {
    canvas.drawRect(courtRect, Paint()..color = theme.courtColor);
  }

  /// Tints the two goal areas so the 6 m zones read at a glance.
  void _paintGoalAreas(Canvas canvas, Float64List matrix) {
    final fill = Paint()..color = theme.goalAreaColor;
    for (final d in _geometry.goalAreaLines) {
      // The D is an open path; closing it along the goal line makes it fill.
      final closed = Path.from(d)..close();
      canvas.drawPath(closed.transform(matrix), fill);
    }
  }

  /// The 9 m line is dashed and, by construction, runs past the sidelines —
  /// so it is clipped to the playing area exactly as painted on a real floor.
  void _paintFreeThrowLines(
    Canvas canvas,
    Float64List matrix,
    Rect courtRect,
    Paint linePaint,
  ) {
    canvas.save();
    canvas.clipRect(courtRect);
    for (final path in _geometry.freeThrowLines) {
      final dashed = _dashPath(
        path.transform(matrix),
        dashLength: linePaint.strokeWidth * 8,
        gapLength: linePaint.strokeWidth * 6,
      );
      canvas.drawPath(dashed, linePaint);
    }
    canvas.restore();
  }

  void _paintGoals(Canvas canvas, Float64List matrix, double strokeWidth) {
    final goalPaint = Paint()
      ..color = theme.goalColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.6
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    for (final path in _geometry.goals) {
      canvas.drawPath(path.transform(matrix), goalPaint);
    }
  }

  /// Converts a path into a dashed equivalent by walking its metrics.
  ///
  /// Dash lengths are in screen pixels, so the pattern stays visually even
  /// regardless of zoom.
  static Path _dashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final result = Path();
    final period = dashLength + gapLength;
    if (period <= 0) return source;

    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += period;
      }
    }
    return result;
  }

  /// Builds the uniform scale-then-translate matrix that [Path.transform]
  /// expects: a 4x4 in **column-major** order, so translation occupies
  /// indices 12 and 13.
  ///
  /// Written out by hand rather than pulled from `vector_math` to keep the
  /// dependency list minimal — this is the only matrix the renderer needs.
  static Float64List _worldToScreenMatrix(CourtViewTransform transform) {
    final s = transform.scale;
    final m = Float64List(16);
    m[0] = s; // column 0: x scale
    m[5] = s; // column 1: y scale
    m[10] = 1.0; // column 2: z untouched
    m[12] = transform.originOnScreen.dx; // column 3: translation
    m[13] = transform.originOnScreen.dy;
    m[15] = 1.0;
    return m;
  }

  @override
  bool shouldRepaint(HandballCourtLayer oldLayer) =>
      oldLayer.court != court || oldLayer.theme != theme;
}

/// Fills the area surrounding the court, where off-court receivers live.
class CourtSurroundLayer extends CourtLayer {
  final CourtTheme theme;

  const CourtSurroundLayer({this.theme = const CourtTheme()});

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    canvas.drawRect(
      Offset.zero & transform.viewport,
      Paint()..color = theme.surroundColor,
    );
  }

  @override
  bool shouldRepaint(CourtSurroundLayer oldLayer) => oldLayer.theme != theme;
}

/// Debug helper: a 1 m grid over the visible world.
///
/// Useful while verifying that the metre scale is honest; off by default.
class MetreGridLayer extends CourtLayer {
  final Color color;
  final double stepMeters;

  const MetreGridLayer({
    this.color = Colors.white24,
    this.stepMeters = 1.0,
  });

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    final world = transform.visibleWorld;

    for (var x = world.left.ceilToDouble(); x <= world.right; x += stepMeters) {
      canvas.drawLine(
        transform.worldToScreen(Offset(x, world.top)),
        transform.worldToScreen(Offset(x, world.bottom)),
        paint,
      );
    }
    for (var y = world.top.ceilToDouble(); y <= world.bottom; y += stepMeters) {
      canvas.drawLine(
        transform.worldToScreen(Offset(world.left, y)),
        transform.worldToScreen(Offset(world.right, y)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(MetreGridLayer oldLayer) =>
      oldLayer.color != color || oldLayer.stepMeters != stepMeters;
}
