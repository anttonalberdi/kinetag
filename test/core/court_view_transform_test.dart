import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/core/court_view_transform.dart';

/// The world region the setup view shows: the 40x20 court plus a 5 m margin
/// so that receivers placed outside the playing area stay visible.
const kVisibleWorld = Rect.fromLTRB(-5, -5, 45, 25);

void main() {
  group('CourtViewTransform.fit', () {
    test('uses a single uniform scale for both axes', () {
      // A viewport whose aspect ratio differs from the world region would
      // stretch the court under an anisotropic fit.
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(1000, 1000),
      );

      // 50 m wide, 30 m tall into 1000x1000 -> width is the binding axis,
      // because 1000/50 = 20 px/m is tighter than 1000/30 = 33.3 px/m.
      expect(t.scale, closeTo(1000 / 50, 1e-9));

      // One metre is the same number of pixels along X and Y.
      final oneMetreX = t.worldToScreen(const Offset(1, 0)) -
          t.worldToScreen(const Offset(0, 0));
      final oneMetreY = t.worldToScreen(const Offset(0, 1)) -
          t.worldToScreen(const Offset(0, 0));
      expect(oneMetreX.dx, closeTo(oneMetreY.dy, 1e-9));
    });

    test('fits within the viewport on both axes', () {
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(800, 600),
      );
      final drawn = t.worldRectToScreen(kVisibleWorld);

      expect(drawn.width, lessThanOrEqualTo(800 + 1e-9));
      expect(drawn.height, lessThanOrEqualTo(600 + 1e-9));
    });

    test('centres the visible world inside the viewport', () {
      const viewport = Size(800, 600);
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: viewport,
      );
      final drawn = t.worldRectToScreen(kVisibleWorld);

      // Equal slack on left/right and top/bottom.
      expect(drawn.left, closeTo(viewport.width - drawn.right, 1e-9));
      expect(drawn.top, closeTo(viewport.height - drawn.bottom, 1e-9));
    });

    test('honours padding', () {
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(800, 600),
        padding: 20,
      );
      final drawn = t.worldRectToScreen(kVisibleWorld);

      expect(drawn.width, lessThanOrEqualTo(800 - 40 + 1e-9));
      expect(drawn.height, lessThanOrEqualTo(600 - 40 + 1e-9));
    });

    test('never produces a negative scale when padding exceeds the viewport',
        () {
      // A transient tiny viewport during window resize must not mirror the
      // scene, which a negative scale would do.
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(10, 10),
        padding: 50,
      );
      expect(t.scale, greaterThan(0));
    });
  });

  group('world <-> screen round trip', () {
    test('screenToWorld inverts worldToScreen', () {
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(1280, 720),
      );

      const probes = [
        Offset(0, 0), // court top-left
        Offset(40, 20), // court bottom-right
        Offset(20, 10), // centre spot
        Offset(-1.2, -0.8), // a receiver outside the court
        Offset(44.9, 24.9), // far corner of the visible region
      ];

      for (final world in probes) {
        final back = t.screenToWorld(t.worldToScreen(world));
        expect(back.dx, closeTo(world.dx, 1e-9), reason: 'x for $world');
        expect(back.dy, closeTo(world.dy, 1e-9), reason: 'y for $world');
      }
    });

    test('metre/pixel length conversions round trip', () {
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(1280, 720),
      );
      expect(t.pixelsToMetres(t.metresToPixels(6.0)), closeTo(6.0, 1e-9));
    });
  });

  group('resize invariance', () {
    test('a physical point keeps its world coordinate across window sizes', () {
      // This is the property that makes dragging a receiver safe: the same
      // world point must survive any viewport change.
      const sizes = [
        Size(800, 600),
        Size(1440, 900),
        Size(600, 1200), // portrait
        Size(2560, 1440),
      ];

      const world = Offset(12.5, 7.25);

      for (final size in sizes) {
        final t = CourtViewTransform.fit(
          visibleWorld: kVisibleWorld,
          viewport: size,
        );
        final back = t.screenToWorld(t.worldToScreen(world));
        expect(back.dx, closeTo(world.dx, 1e-9), reason: 'x at $size');
        expect(back.dy, closeTo(world.dy, 1e-9), reason: 'y at $size');
      }
    });

    test('court centre stays at the viewport centre when world is centred', () {
      // kVisibleWorld is symmetric about the court centre (20,10), so the
      // court centre must land exactly at the middle of the viewport.
      const viewport = Size(1000, 800);
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: viewport,
      );
      final centre = t.worldToScreen(const Offset(20, 10));

      expect(centre.dx, closeTo(viewport.width / 2, 1e-9));
      expect(centre.dy, closeTo(viewport.height / 2, 1e-9));
    });
  });

  group('orientation', () {
    test('+Y points down the screen', () {
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(1000, 800),
      );
      final top = t.worldToScreen(const Offset(20, 0));
      final bottom = t.worldToScreen(const Offset(20, 20));

      expect(bottom.dy, greaterThan(top.dy));
    });

    test('+X points right across the screen', () {
      final t = CourtViewTransform.fit(
        visibleWorld: kVisibleWorld,
        viewport: const Size(1000, 800),
      );
      final left = t.worldToScreen(const Offset(0, 10));
      final right = t.worldToScreen(const Offset(40, 10));

      expect(right.dx, greaterThan(left.dx));
    });
  });
}
