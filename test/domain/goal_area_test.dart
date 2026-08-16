import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';

void main() {
  final court = Court.handball();
  const area = GoalArea(Court(
    id: 'c',
    name: 'c',
    sport: SportType.handball,
    widthMeters: 40,
    heightMeters: 20,
  ));

  group('containment', () {
    test('the six metres in front of each goal are inside', () {
      expect(area.contains(3, 10), isTrue);
      expect(area.contains(court.widthMeters - 3, 10), isTrue);
    });

    test('the middle of the court is outside', () {
      expect(area.contains(20, 10), isFalse);
      expect(area.contains(20, 1), isFalse);
    });

    test('the line itself is the boundary, six metres out', () {
      // Straight out from the goal centre: 5.99 m in, 6.01 m out.
      expect(area.contains(5.99, 10), isTrue);
      expect(area.contains(6.01, 10), isFalse);
    });

    test('the corners of the D are struck from the posts, not the centre', () {
      // The arc is a 6 m circle about the inner rear corner of each post, so
      // level with a post the zone still reaches 6 m up the court…
      expect(area.contains(5.5, 8.5), isTrue);
      // …while out beyond the post the same x is already clear of it.
      expect(area.contains(5.5, 2.0), isFalse);
    });

    test('a margin grows the zone without moving it', () {
      expect(area.contains(6.2, 10), isFalse);
      expect(area.contains(6.2, 10, margin: 0.35), isTrue);
    });
  });

  group('pushOut', () {
    test('leaves a point outside exactly where it was', () {
      expect(area.pushOut(20, 10), (20.0, 10.0));
    });

    test('puts a point in front of the goal on the line', () {
      final (x, y) = area.pushOut(2, 10);
      expect(x, closeTo(GoalArea.radiusMeters, 1e-9));
      expect(y, closeTo(10, 1e-9));
    });

    test('pushes radially from the nearest post out to the side', () {
      final (x, y) = area.pushOut(2, 5, margin: 0.35);
      // The post is the centre of the arc there, so the result sits at the
      // radius from it rather than at a fixed distance from the goal line.
      final distanceToPost = math.sqrt(x * x + math.pow(y - 8.5, 2));
      expect(distanceToPost, closeTo(GoalArea.radiusMeters + 0.35, 1e-9));
    });

    test('respects the margin it is given', () {
      final (x, _) = area.pushOut(2, 10, margin: 0.35);
      expect(x, closeTo(GoalArea.radiusMeters + 0.35, 1e-9));
    });

    test('sends a point on the goal line up the court, not through it', () {
      final home = area.pushOut(0, 10);
      expect(home.$1, closeTo(GoalArea.radiusMeters, 1e-9));

      final away = area.pushOut(court.widthMeters, 10);
      expect(away.$1,
          closeTo(court.widthMeters - GoalArea.radiusMeters, 1e-9));
    });

    test('handles the away end the same way as the home end', () {
      final (x, y) = area.pushOut(court.widthMeters - 2, 10);
      expect(x, closeTo(court.widthMeters - GoalArea.radiusMeters, 1e-9));
      expect(y, closeTo(10, 1e-9));
    });

    test('what it returns is never still inside', () {
      // The property that matters to the simulator, over the whole floor.
      for (var x = 0.0; x <= court.widthMeters; x += 0.25) {
        for (var y = 0.0; y <= court.heightMeters; y += 0.25) {
          final (px, py) = area.pushOut(x, y, margin: 0.35);
          expect(area.contains(px, py, margin: 0.35 - 1e-9), isFalse,
              reason: '($x, $y) came out at ($px, $py)');
        }
      }
    });
  });

  test('the painter draws the line this measures', () {
    // One source of truth: the 6 m line on screen and the 6 m line the
    // simulator keeps players out of are the same number.
    expect(GoalArea.radiusMeters, 6.0);
    expect(GoalArea.goalWidthMeters, 3.0);
  });
}
