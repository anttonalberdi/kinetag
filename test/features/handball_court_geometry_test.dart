import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/court/handball_court_geometry.dart';

/// Asserts that [path] passes through [point] (within [tolerance] metres).
void expectPathContains(Path path, Offset point, {double tolerance = 0.02}) {
  for (final metric in path.computeMetrics()) {
    // Walk the path in 1 cm steps — fine enough for a 6-9 m arc.
    final steps = (metric.length / 0.01).ceil().clamp(1, 200000);
    for (var i = 0; i <= steps; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / steps);
      if (tangent != null && (tangent.position - point).distance <= tolerance) {
        return;
      }
    }
  }
  fail('Path does not pass through $point');
}

void main() {
  final geometry = HandballCourtGeometry(Court.handball());

  group('court bounds', () {
    test('playing area is 40 x 20 m anchored at the origin', () {
      expect(geometry.bounds, const Rect.fromLTWH(0, 0, 40, 20));
    });

    test('centre line bisects the court at x = 20', () {
      expect(geometry.centreLine.getBounds().left, closeTo(20, 1e-9));
      expect(geometry.centreLine.getBounds().right, closeTo(20, 1e-9));
    });
  });

  group('goal-area (6 m) line', () {
    test('left D reaches its apex 6 m in front of the goal', () {
      final d = geometry.dLine(goalX: 0, radius: 6, opensRight: true);
      // Apex segment runs from (6, 8.5) to (6, 11.5).
      expectPathContains(d, const Offset(6, 8.5));
      expectPathContains(d, const Offset(6, 11.5));
    });

    test('left D meets the goal line 6 m either side of the posts', () {
      final d = geometry.dLine(goalX: 0, radius: 6, opensRight: true);
      // Posts sit at y = 8.5 and 11.5; arcs of radius 6 land at 2.5 and 17.5.
      expectPathContains(d, const Offset(0, 2.5));
      expectPathContains(d, const Offset(0, 17.5));
    });

    test('right D mirrors the left one', () {
      final d = geometry.dLine(goalX: 40, radius: 6, opensRight: false);
      expectPathContains(d, const Offset(34, 8.5));
      expectPathContains(d, const Offset(34, 11.5));
      expectPathContains(d, const Offset(40, 2.5));
      expectPathContains(d, const Offset(40, 17.5));
    });

    test('stays within the court', () {
      for (final d in geometry.goalAreaLines) {
        final b = d.getBounds();
        expect(b.top, greaterThanOrEqualTo(-1e-6));
        expect(b.bottom, lessThanOrEqualTo(20 + 1e-6));
        expect(b.left, greaterThanOrEqualTo(-1e-6));
        expect(b.right, lessThanOrEqualTo(40 + 1e-6));
      }
    });
  });

  group('free-throw (9 m) line', () {
    test('left D reaches its apex 9 m in front of the goal', () {
      final d = geometry.dLine(goalX: 0, radius: 9, opensRight: true);
      expectPathContains(d, const Offset(9, 8.5));
      expectPathContains(d, const Offset(9, 11.5));
    });

    test('extends past the sidelines, so the painter must clip it', () {
      // 8.5 - 9 = -0.5 and 11.5 + 9 = 20.5, both outside 0..20.
      final bounds =
          geometry.dLine(goalX: 0, radius: 9, opensRight: true).getBounds();
      expect(bounds.top, lessThan(0));
      expect(bounds.bottom, greaterThan(20));
    });
  });

  group('penalty and goalkeeper marks', () {
    test('7 m lines sit 7 m from each goal and are 1 m long', () {
      final left = geometry.sevenMetreLines[0].getBounds();
      expect(left.left, closeTo(7, 1e-9));
      expect(left.height, closeTo(1.0, 1e-9));
      expect(left.center.dy, closeTo(10, 1e-9));

      final right = geometry.sevenMetreLines[1].getBounds();
      expect(right.left, closeTo(33, 1e-9));
    });

    test('4 m goalkeeper lines are 15 cm long', () {
      final left = geometry.goalkeeperLines[0].getBounds();
      expect(left.left, closeTo(4, 1e-9));
      // Path bounds are float32 internally, so 0.15 lands ~4e-7 off.
      expect(left.height, closeTo(0.15, 1e-6));
    });
  });

  group('goals', () {
    test('are 3 m wide and centred on the goal line', () {
      final left = geometry.goals[0].getBounds();
      expect(left.height, closeTo(3.0, 1e-9));
      expect(left.center.dy, closeTo(10, 1e-9));
      // Drawn outside the court, behind the goal line.
      expect(left.left, lessThan(0));

      final right = geometry.goals[1].getBounds();
      expect(right.right, greaterThan(40));
    });
  });
}
