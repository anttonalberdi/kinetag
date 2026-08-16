import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/court/handball_court_layer.dart';

/// Wraps the canvas in a fixed-size box so the transform is deterministic.
Widget harness({
  required Size size,
  required Court court,
  void Function(Offset world)? onTap,
  double padding = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: CourtCanvas(
            court: court,
            paddingPixels: padding,
            onWorldTapDown:
                onTap == null ? null : (world, _) => onTap(world),
            layers: [
              const CourtSurroundLayer(),
              HandballCourtLayer(court: court),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  final court = Court.handball();

  testWidgets('renders without error at a typical desktop size',
      (tester) async {
    await tester.pumpWidget(
        harness(size: const Size(1200, 700), court: court));
    expect(find.byType(CourtCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a degenerate zero-height box', (tester) async {
    // Can happen transiently during window resize.
    await tester
        .pumpWidget(harness(size: const Size(300, 0), court: court));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports the court centre for a tap at the widget centre',
      (tester) async {
    Offset? tapped;
    await tester.pumpWidget(harness(
      size: const Size(1000, 600),
      court: court,
      onTap: (world) => tapped = world,
    ));

    await tester.tapAt(tester.getCenter(find.byType(CourtCanvas)));
    await tester.pump();

    // The visible world (-5..45, -5..25) is symmetric about the court
    // centre, so the widget centre must map to (20, 10).
    expect(tapped, isNotNull);
    expect(tapped!.dx, closeTo(20.0, 1e-6));
    expect(tapped!.dy, closeTo(10.0, 1e-6));
  });

  testWidgets('a tap maps to the same world point regardless of window size',
      (tester) async {
    // The property that makes receiver dragging safe under resize.
    final results = <Offset>[];

    for (final size in const [
      Size(800, 480),
      Size(1440, 900),
      Size(600, 900),
    ]) {
      Offset? tapped;
      await tester.pumpWidget(harness(
        size: size,
        court: court,
        onTap: (world) => tapped = world,
      ));
      await tester.tapAt(tester.getCenter(find.byType(CourtCanvas)));
      await tester.pump();
      results.add(tapped!);
    }

    for (final r in results) {
      expect(r.dx, closeTo(20.0, 1e-6));
      expect(r.dy, closeTo(10.0, 1e-6));
    }
  });

  test('visibleWorldFor surrounds the playing area by the given margin', () {
    final canvas = CourtCanvas(court: court, layers: const [], marginMeters: 5);

    // Receivers outside the court must remain on screen.
    expect(canvas.visibleWorldFor(court), const Rect.fromLTRB(-5, -5, 45, 25));
  });

  test('margin is configurable without touching the playing area', () {
    final canvas =
        CourtCanvas(court: court, layers: const [], marginMeters: 2.5);

    expect(canvas.visibleWorldFor(court), const Rect.fromLTRB(-2.5, -2.5, 42.5, 22.5));
    // The court itself is unchanged: still 0..40 by 0..20.
    expect(court.widthMeters, 40.0);
    expect(court.heightMeters, 20.0);
  });
}
