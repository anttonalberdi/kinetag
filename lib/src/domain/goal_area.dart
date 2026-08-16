import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'court.dart';

/// The two goal areas ("6 m zones") of a handball court, as geometry rather
/// than as markings.
///
/// `HandballCourtGeometry` already knows the same shape, but it expresses it as
/// `dart:ui` [Path]s for painting, which a headless simulation cannot use and a
/// test cannot query for containment. This is the same construction reduced to
/// the one question the rest of the app asks of it: *is this player standing in
/// the goal area, and if so where is the nearest point outside it?* Both build
/// on the constants declared here, so the line that is drawn and the line that
/// is enforced can never drift apart.
///
/// ## The construction
///
/// The goal area is every point within [radiusMeters] of the goal line
/// **segment between the posts** — that single definition produces the
/// straight 3 m front and the two quarter-circle arcs at once, because the
/// nearest point on the segment is a post for anything off to the side and the
/// segment itself for anything in front.
///
/// Distances are absolute metres, not fractions of the court: the 6 m line is
/// 6 m from the goal on a regulation floor and on a small training pitch
/// alike, exactly as the painter draws it.
@immutable
class GoalArea {
  final Court court;

  const GoalArea(this.court);

  /// Distance between the goalposts, in metres (IHF: 3 m).
  static const double goalWidthMeters = 3.0;

  /// Radius of the goal-area line, in metres (IHF: 6 m).
  static const double radiusMeters = 6.0;

  double get _midY => court.heightMeters / 2;

  /// Offset of each post from the goal centre.
  static const double _postOffset = goalWidthMeters / 2;

  /// The x of each goal line: the home end and the away end.
  List<double> get _goalLines => [0.0, court.widthMeters];

  /// Whether ([x], [y]) lies inside either goal area, grown by [margin].
  bool contains(double x, double y, {double margin = 0}) {
    for (final goalX in _goalLines) {
      if (_distanceToGoal(goalX, x, y) < radiusMeters + margin) return true;
    }
    return false;
  }

  /// ([x], [y]) moved to the closest point at least [margin] outside both goal
  /// areas, or returned unchanged when it is already clear of them.
  ///
  /// The move is radial — straight away from the nearest point of the goal
  /// line — which is the shortest way out and therefore the one that disturbs
  /// a trajectory least. A point exactly on the goal line between the posts has
  /// no such direction, so it is pushed straight up the court instead.
  ///
  /// The two ends are resolved in turn. On any court wide enough for the areas
  /// not to overlap — every real one, since two 6 m zones need 12 m — that is
  /// the same as resolving them together.
  (double, double) pushOut(double x, double y, {double margin = 0}) {
    var px = x;
    var py = y;

    for (final goalX in _goalLines) {
      final limit = radiusMeters + margin;
      final closestY = py.clamp(_midY - _postOffset, _midY + _postOffset);
      final dx = px - goalX;
      final dy = py - closestY;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance >= limit) continue;

      if (distance < 1e-9) {
        // On the goal line itself: head for the middle of the court.
        px = goalX + (goalX == 0 ? limit : -limit);
        py = closestY;
        continue;
      }

      px = goalX + dx / distance * limit;
      py = closestY + dy / distance * limit;
    }

    return (px, py);
  }

  /// Distance from ([x], [y]) to the goal line segment at [goalX].
  double _distanceToGoal(double goalX, double x, double y) {
    final closestY = y.clamp(_midY - _postOffset, _midY + _postOffset);
    final dx = x - goalX;
    final dy = y - closestY;
    return math.sqrt(dx * dx + dy * dy);
  }
}
