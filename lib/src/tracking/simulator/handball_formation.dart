import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../domain/domain.dart';

/// A position in a small-sided handball formation.
///
/// Every slot has a place in the defensive line and in the attacking shape.
/// [anchorAt] blends between them as possession travels from one goal to the
/// other. Coordinates are team-local: this side defends `x = 0` and attacks
/// `+x`; [MatchSimulation] rotates the result for the other team.
@immutable
class HandballFormationSlot {
  final int defenceIndex;
  final int fieldPlayerCount;
  final int? attackIndex;
  final int attackPerimeterCount;

  const HandballFormationSlot._({
    required this.defenceIndex,
    required this.fieldPlayerCount,
    required this.attackIndex,
    required this.attackPerimeterCount,
  });

  /// Whether this slot moves inside the attacking perimeter as the pivot.
  bool get attacksAsPivot => attackIndex == null;

  /// The centre of this slot while defending its own goal.
  (double, double) defenceAnchor(Court court) => HandballFormation._arcAnchor(
    court: court,
    distanceFromGoalMeters: HandballFormation.defenceDistanceMeters,
    sidelineInsetMeters: HandballFormation.defenceSidelineInsetMeters,
    index: defenceIndex,
    count: fieldPlayerCount,
  );

  /// The centre of this slot while attacking the opposite goal.
  (double, double) attackAnchor(Court court) {
    if (attacksAsPivot) {
      return (
        court.widthMeters - HandballFormation.pivotDistanceMeters,
        court.heightMeters / 2 + HandballFormation.pivotLateralOffsetMeters,
      );
    }

    final fromGoal = HandballFormation._arcAnchor(
      court: court,
      distanceFromGoalMeters: HandballFormation.attackDistanceMeters,
      sidelineInsetMeters: HandballFormation.attackSidelineInsetMeters,
      index: attackIndex!,
      count: attackPerimeterCount,
    );
    return (court.widthMeters - fromGoal.$1, fromGoal.$2);
  }

  /// Formation centre at [phase], where -1 is defence and +1 is attack.
  (double, double) anchorAt(
    Court court,
    double phase, {
    HandballFormationSlot? attackDestination,
  }) {
    final defence = defenceAnchor(court);
    final attack = (attackDestination ?? this).attackAnchor(court);
    final attackWeight = ((phase + 1) / 2).clamp(0.0, 1.0);

    return (
      defence.$1 + (attack.$1 - defence.$1) * attackWeight,
      defence.$2 + (attack.$2 - defence.$2) * attackWeight,
    );
  }
}

/// Geometry for realistic 4-, 5-, and 6-field-player handball shapes.
///
/// The arcs are offsets from the 3 m goal-line segment, matching [GoalArea]'s
/// construction. Equal distance along that D-shaped path gives every defender
/// a comparable piece of the goal circle instead of spacing them only by `y`,
/// which bunches central players and leaves the curved shoulders empty.
abstract final class HandballFormation {
  /// Defensive line: close to, but not standing on, the 6 m boundary.
  static const double defenceDistanceMeters = 7.0;

  /// Back-court attacking line, centred on the dashed 9 m boundary.
  static const double attackDistanceMeters = 9.1;

  /// The pivot stays just outside the goal area among the defenders.
  static const double pivotDistanceMeters = 7.0;

  /// How far the defensive shape stops short of each sideline.
  static const double defenceSidelineInsetMeters = 3.0;

  /// Attackers use more of the court width, especially the two wings.
  static const double attackSidelineInsetMeters = 0.8;

  /// Keeps the pivot off the central back's lane and between defenders.
  static const double pivotLateralOffsetMeters = 1.3;

  /// Builds slots in defensive left-to-right order.
  ///
  /// Four- and five-player attacks use the whole side on the perimeter. A
  /// six-player attack removes [pivotDefenceIndex] from that perimeter and
  /// puts it at the 6 m line. If no roster role identifies a pivot, the
  /// right-centre defensive slot takes that job.
  static List<HandballFormationSlot> slots(
    int fieldPlayerCount, {
    int? pivotDefenceIndex,
  }) {
    assert(fieldPlayerCount > 0, 'a formation needs at least one player');

    final usesPivot = fieldPlayerCount == 6;
    final pivotIndex = usesPivot
        ? (pivotDefenceIndex ?? fieldPlayerCount ~/ 2).clamp(
            0,
            fieldPlayerCount - 1,
          )
        : -1;
    final perimeterCount = fieldPlayerCount - (usesPivot ? 1 : 0);
    var attackIndex = 0;

    return [
      for (
        var defenceIndex = 0;
        defenceIndex < fieldPlayerCount;
        defenceIndex++
      )
        if (defenceIndex == pivotIndex)
          HandballFormationSlot._(
            defenceIndex: defenceIndex,
            fieldPlayerCount: fieldPlayerCount,
            attackIndex: null,
            attackPerimeterCount: perimeterCount,
          )
        else
          HandballFormationSlot._(
            defenceIndex: defenceIndex,
            fieldPlayerCount: fieldPlayerCount,
            attackIndex: attackIndex++,
            attackPerimeterCount: perimeterCount,
          ),
    ];
  }

  /// A point [distanceFromGoalMeters] from the goal-line segment.
  ///
  /// The usable path comprises a lower circular shoulder, the 3 m straight
  /// section in front of goal, and an upper circular shoulder. Players are
  /// placed at the centre of equal-length pieces of that path, leaving half a
  /// player's share free at each end instead of pinning wings to a sideline.
  static (double, double) _arcAnchor({
    required Court court,
    required double distanceFromGoalMeters,
    required double sidelineInsetMeters,
    required int index,
    required int count,
  }) {
    final midY = court.heightMeters / 2;
    final lowerPostY = midY - GoalArea.goalWidthMeters / 2;
    final upperPostY = midY + GoalArea.goalWidthMeters / 2;
    final lateralReach = (lowerPostY - sidelineInsetMeters).clamp(
      0.0,
      distanceFromGoalMeters - 1e-6,
    );
    final shoulderAngle = math.asin(lateralReach / distanceFromGoalMeters);
    final shoulderLength = distanceFromGoalMeters * shoulderAngle;
    const frontLength = GoalArea.goalWidthMeters;
    final pathLength = shoulderLength * 2 + frontLength;
    final along = pathLength * (index + 0.5) / count;

    if (along < shoulderLength) {
      final angle = -shoulderAngle + along / distanceFromGoalMeters;
      return (
        distanceFromGoalMeters * math.cos(angle),
        lowerPostY + distanceFromGoalMeters * math.sin(angle),
      );
    }

    if (along <= shoulderLength + frontLength) {
      return (distanceFromGoalMeters, lowerPostY + along - shoulderLength);
    }

    final angle =
        (along - shoulderLength - frontLength) / distanceFromGoalMeters;
    return (
      distanceFromGoalMeters * math.cos(angle),
      upperPostY + distanceFromGoalMeters * math.sin(angle),
    );
  }
}
