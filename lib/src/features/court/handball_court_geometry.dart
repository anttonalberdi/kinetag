import 'dart:math' as math;
import 'dart:ui';

import '../../domain/court.dart';
import '../../domain/goal_area.dart';

/// Handball court markings expressed as paths in **world coordinates
/// (metres)**.
///
/// Building the geometry in world space and transforming it at paint time
/// (rather than recomputing it in pixels every frame) keeps the markings
/// exactly consistent under resize and makes the maths unit-testable without
/// a render surface.
///
/// ## Regulation dimensions (IHF)
///
/// * Court: 40 m x 20 m.
/// * Goal: 3 m wide, centred on each goal line.
/// * Goal-area line ("6 m line"): a 3 m straight segment 6 m in front of the
///   goal, joined to the goal line at each end by quarter circles of radius
///   6 m centred on the **inner rear corners of the goalposts**.
/// * Free-throw line ("9 m line"): the same construction with radius 9 m,
///   drawn dashed. Its arcs run past the sidelines, so the painter clips it
///   to the court — which is how it appears on a real floor.
/// * 7 m line: 1 m long, parallel to the goal line, 7 m from it.
/// * Goalkeeper restraining line ("4 m line"): 15 cm long, 4 m from the goal.
///
/// ## Angle convention
///
/// World +Y points down, so in [Path.arcTo] angle 0 is +X (right) and a
/// positive sweep rotates towards +Y, i.e. clockwise as drawn on screen.
class HandballCourtGeometry {
  final Court court;

  const HandballCourtGeometry(this.court);

  // The goal area is also enforced, not only drawn — the simulator keeps
  // outfield players out of it — so its dimensions live in [GoalArea], where
  // pure-Dart code can reach them, and are re-exported here for the painter.
  static const double goalWidth = GoalArea.goalWidthMeters;
  static const double goalAreaRadius = GoalArea.radiusMeters;
  static const double freeThrowRadius = 9.0;
  static const double sevenMetreLineLength = 1.0;
  static const double goalkeeperLineLength = 0.15;

  /// Visual depth of the drawn goal box. Not a regulation playing dimension.
  static const double goalDepth = 1.0;

  double get _midY => court.heightMeters / 2;
  double get _rightGoalX => court.widthMeters;

  /// Half the goal width — the offset of each post from the goal centre.
  double get _postOffset => goalWidth / 2;

  /// The playing area, in metres.
  Rect get bounds =>
      Rect.fromLTWH(0, 0, court.widthMeters, court.heightMeters);

  /// The court outline.
  Path get boundary => Path()..addRect(bounds);

  /// The halfway line.
  Path get centreLine => Path()
    ..moveTo(court.widthMeters / 2, 0)
    ..lineTo(court.widthMeters / 2, court.heightMeters);

  /// Goal-area ("6 m") lines for both ends. These stay inside the court.
  List<Path> get goalAreaLines => [
        dLine(goalX: 0, radius: goalAreaRadius, opensRight: true),
        dLine(goalX: _rightGoalX, radius: goalAreaRadius, opensRight: false),
      ];

  /// Free-throw ("9 m") lines for both ends.
  ///
  /// These extend beyond the sidelines by construction; the painter is
  /// responsible for clipping them to [bounds].
  List<Path> get freeThrowLines => [
        dLine(goalX: 0, radius: freeThrowRadius, opensRight: true),
        dLine(goalX: _rightGoalX, radius: freeThrowRadius, opensRight: false),
      ];

  /// The two 7 m penalty lines.
  List<Path> get sevenMetreLines => [
        _goalParallelTick(x: 7.0, length: sevenMetreLineLength),
        _goalParallelTick(
            x: _rightGoalX - 7.0, length: sevenMetreLineLength),
      ];

  /// The two 4 m goalkeeper restraining lines.
  List<Path> get goalkeeperLines => [
        _goalParallelTick(x: 4.0, length: goalkeeperLineLength),
        _goalParallelTick(
            x: _rightGoalX - 4.0, length: goalkeeperLineLength),
      ];

  /// The goal boxes, drawn just outside each goal line.
  List<Path> get goals => [
        Path()
          ..moveTo(0, _midY - _postOffset)
          ..lineTo(-goalDepth, _midY - _postOffset)
          ..lineTo(-goalDepth, _midY + _postOffset)
          ..lineTo(0, _midY + _postOffset),
        Path()
          ..moveTo(_rightGoalX, _midY - _postOffset)
          ..lineTo(_rightGoalX + goalDepth, _midY - _postOffset)
          ..lineTo(_rightGoalX + goalDepth, _midY + _postOffset)
          ..lineTo(_rightGoalX, _midY + _postOffset),
      ];

  /// A short line parallel to the goal line (i.e. running along Y), centred
  /// on the goal axis at distance [x] from the left sideline.
  Path _goalParallelTick({required double x, required double length}) => Path()
    ..moveTo(x, _midY - length / 2)
    ..lineTo(x, _midY + length / 2);

  /// Builds the characteristic "D" shape at one end of the court.
  ///
  /// Two quarter circles of [radius] struck from the goalposts at [goalX],
  /// joined by a straight segment [radius] metres in front of the goal line.
  /// [opensRight] is true for the left-hand goal, whose D opens towards +X.
  ///
  /// Exposed for testing.
  Path dLine({
    required double goalX,
    required double radius,
    required bool opensRight,
  }) {
    final direction = opensRight ? 1.0 : -1.0;
    final apexX = goalX + direction * radius;

    final upperPostY = _midY - _postOffset;
    final lowerPostY = _midY + _postOffset;

    // Sweeping "outward from the goal line" is clockwise for the left goal
    // and anticlockwise for the right goal.
    final sweep = direction * math.pi / 2;

    // The straight segment ends at angle 0 (+X) for the left goal and pi (-X)
    // for the right goal.
    final apexAngle = opensRight ? 0.0 : math.pi;

    return Path()
      // Start on the goal line, at the outer end of the upper arc.
      ..moveTo(goalX, upperPostY - radius)
      // Upper quarter circle: from straight-up (-pi/2) round to the apex.
      ..arcTo(
        Rect.fromCircle(center: Offset(goalX, upperPostY), radius: radius),
        -math.pi / 2,
        sweep,
        false,
      )
      // Straight segment parallel to the goal line.
      ..lineTo(apexX, lowerPostY)
      // Lower quarter circle: from the apex round to straight-down (+pi/2).
      ..arcTo(
        Rect.fromCircle(center: Offset(goalX, lowerPostY), radius: radius),
        apexAngle,
        sweep,
        false,
      );
  }
}
