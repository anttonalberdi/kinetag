import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/court/handball_court_layer.dart';

/// Rasterises the court through the real Flutter compositor.
///
/// This catches painter faults that a pure-geometry test cannot — bad
/// matrices, invalid paths, shader failures — because it drives the same
/// paint path the macOS app uses.
///
/// It also writes the result to `build/court_render.png` (gitignored) so the
/// court can be inspected by eye without taking a screen capture.
void main() {
  testWidgets('court rasterises to a non-blank image', (tester) async {
    final key = GlobalKey();
    final court = Court.handball();

    tester.view.physicalSize = const ui.Size(1400, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: CourtCanvas(
              court: court,
              layers: [
                const CourtSurroundLayer(),
                const MetreGridLayer(),
                HandballCourtLayer(court: court),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);

      expect(image.width, 2800);
      expect(image.height, 1520);

      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(png, isNotNull);
      // A blank or failed render compresses to almost nothing; the court has
      // markings, a grid and two goals, so it is comfortably larger.
      expect(png!.lengthInBytes, greaterThan(10000));

      final outDir = Directory('build');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      File('build/court_render.png')
          .writeAsBytesSync(png.buffer.asUint8List());

      // The playing surface must actually cover the court. Sampling a single
      // pixel is brittle — the exact centre lands on the centre line — so
      // count green coverage across the whole image instead.
      //
      // The court (40x20 m) fills 40*20 / (50*30) ~= 53% of the fitted
      // visible world, minus markings, so a third of the frame is a safe
      // lower bound and still fails loudly on a blank or black render.
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var greenPixels = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        final r = pixels.getUint8(i);
        final g = pixels.getUint8(i + 1);
        final b = pixels.getUint8(i + 2);
        if (g > r + 20 && g > b + 20) greenPixels++;
      }
      final totalPixels = image.width * image.height;
      expect(
        greenPixels / totalPixels,
        greaterThan(0.33),
        reason: 'playing surface should dominate the frame',
      );
    });
  });
}
