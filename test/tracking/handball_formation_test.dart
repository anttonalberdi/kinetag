import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/tracking/simulator/handball_formation.dart';
import 'package:kinetag/src/tracking/simulator/match_simulation.dart';
import 'package:kinetag/src/tracking/simulator/simulated_squad.dart';

void main() {
  final court = Court.handball();

  group('handball formations', () {
    for (final count in [4, 5, 6]) {
      test('$count defenders share the 6 m arc without bunching', () {
        final positions = [
          for (final slot in HandballFormation.slots(count))
            slot.defenceAnchor(court),
        ];

        for (final position in positions) {
          expect(
            _distanceToGoalLine(court, position),
            closeTo(HandballFormation.defenceDistanceMeters, 1e-9),
          );
        }
        expect(_minimumSeparation(positions), greaterThan(2.3));
        expect(
          positions.last.$2 - positions.first.$2,
          greaterThan(8.0),
          reason: 'the formation should cover both shoulders of the goal area',
        );
      });
    }

    for (final count in [4, 5]) {
      test('$count attackers recover to a spaced 10 m line', () {
        final slots = HandballFormation.slots(count);
        final positions = [for (final slot in slots) slot.attackAnchor(court)];

        expect(slots.where((slot) => slot.attacksAsPivot), isEmpty);
        expect(HandballFormation.attackDistanceMeters, 10.0);
        for (final position in positions) {
          expect(
            _distanceToGoalLine(court, position, attacksRight: true),
            closeTo(HandballFormation.attackDistanceMeters, 1e-9),
          );
        }
        expect(_minimumSeparation(positions), greaterThan(3.5));
      });
    }

    test('6-player attack has five perimeter players and one pivot', () {
      // Slot 2 represents a declared pivot in the roster. Its defensive place
      // remains part of the evenly spaced line, but its attacking place moves
      // inside the five-player perimeter.
      final slots = HandballFormation.slots(6, pivotDefenceIndex: 2);
      final pivot = slots.singleWhere((slot) => slot.attacksAsPivot);
      final perimeter = slots.where((slot) => !slot.attacksAsPivot).toList();

      expect(pivot.defenceIndex, 2);
      expect(perimeter, hasLength(5));
      expect(
        _distanceToGoalLine(
          court,
          pivot.attackAnchor(court),
          attacksRight: true,
        ),
        closeTo(HandballFormation.pivotDistanceMeters, 1e-9),
      );
      for (final slot in perimeter) {
        expect(
          _distanceToGoalLine(
            court,
            slot.attackAnchor(court),
            attacksRight: true,
          ),
          closeTo(HandballFormation.attackDistanceMeters, 1e-9),
        );
      }

      final positions = [for (final slot in slots) slot.attackAnchor(court)];
      expect(_minimumSeparation(positions), greaterThan(2.4));
    });

    test('formation movement blends continuously between both lines', () {
      final slot = HandballFormation.slots(5)[2];
      final defence = slot.anchorAt(court, -1);
      final neutral = slot.anchorAt(court, 0);
      final attack = slot.anchorAt(court, 1);

      expect(defence, slot.defenceAnchor(court));
      expect(attack, slot.attackAnchor(court));
      expect(neutral.$1, closeTo((defence.$1 + attack.$1) / 2, 1e-9));
      expect(neutral.$2, closeTo((defence.$2 + attack.$2) / 2, 1e-9));
    });

    test(
      'the running simulation puts the declared pivot inside the attack',
      () {
        final squad = SimulatedSquad([
          for (final role in PlayerRole.values)
            SimulatedParticipant(
              side: TeamSide.home,
              role: role,
              tagId: role.name,
            ),
        ]);
        final simulation = MatchSimulation(
          court: court,
          squad: squad,
          seed: 17,
          substitutionInterval: Duration.zero,
        );
        final pivotDistances = <double>[];
        final perimeterDistances = <double>[];
        final defenceDistances = <double>[];

        for (var step = 1; step <= 1400; step++) {
          final frame = simulation.advance(
            dtMicros: 50000,
            timestampMicros: step * 50000,
          );
          // Let the acceleration-limited bodies complete one full swing before
          // measuring them near the next attack and defence extrema.
          if (step <= 680) continue;

          if (simulation.playPhase > 0.95) {
            for (final sample in frame.samples) {
              if (sample.tagId == PlayerRole.goalkeeper.name) continue;
              final distance = _distanceToGoalLine(court, (
                sample.x,
                sample.y,
              ), attacksRight: true);
              if (sample.tagId == PlayerRole.pivot.name) {
                pivotDistances.add(distance);
              } else {
                perimeterDistances.add(distance);
              }
            }
          } else if (simulation.playPhase < -0.95) {
            for (final sample in frame.samples) {
              if (sample.tagId == PlayerRole.goalkeeper.name) continue;
              defenceDistances.add(
                _distanceToGoalLine(court, (sample.x, sample.y)),
              );
            }
          }
        }

        expect(_mean(pivotDistances), inInclusiveRange(6.5, 8.0));
        expect(_mean(perimeterDistances), inInclusiveRange(8.5, 10.2));
        expect(_mean(defenceDistances), inInclusiveRange(6.5, 8.2));
      },
    );
  });
}

double _distanceToGoalLine(
  Court court,
  (double, double) position, {
  bool attacksRight = false,
}) {
  final goalX = attacksRight ? court.widthMeters : 0.0;
  final midY = court.heightMeters / 2;
  final halfGoal = GoalArea.goalWidthMeters / 2;
  final closestY = position.$2.clamp(midY - halfGoal, midY + halfGoal);
  final dx = position.$1 - goalX;
  final dy = position.$2 - closestY;
  return math.sqrt(dx * dx + dy * dy);
}

double _minimumSeparation(List<(double, double)> positions) {
  var minimum = double.infinity;
  for (var a = 0; a < positions.length; a++) {
    for (var b = a + 1; b < positions.length; b++) {
      final dx = positions[a].$1 - positions[b].$1;
      final dy = positions[a].$2 - positions[b].$2;
      minimum = math.min(minimum, math.sqrt(dx * dx + dy * dy));
    }
  }
  return minimum;
}

double _mean(List<double> values) =>
    values.reduce((sum, value) => sum + value) / values.length;
