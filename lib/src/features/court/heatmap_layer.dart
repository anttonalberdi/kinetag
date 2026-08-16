import 'dart:ui';

import 'package:flutter/painting.dart';

import '../../analytics/occupancy_grid.dart';
import '../../core/court_view_transform.dart';
import 'court_layer.dart';

/// Paints an [OccupancyGrid] over the playing area as a heatmap.
///
/// The layer draws one rectangle per occupied cell and blurs the result as a
/// whole, rather than blurring the data: the grid stays the measurement it was
/// — a caller can still read a cell's dwell time off it — while the picture
/// reads as the continuous thing movement actually is.
///
/// Nothing here knows about players, teams or sessions. It takes a grid, a
/// colour and an opacity, which is what lets one player's map, a team's map and
/// a whole squad's map be the same layer with different arithmetic behind it.
class HeatmapLayer extends CourtLayer {
  /// The grid to draw, already smoothed for display if the caller wants that.
  final OccupancyGrid grid;

  /// The hue the ramp is built from — the player's or team's own colour, so a
  /// map is identifiable next to the badge and the zone bar that share it.
  final Color color;

  /// Alpha of the busiest cell. Below 1 so the court markings stay readable
  /// under the hottest part of the map, which is exactly where a coach wants
  /// to know whether they are looking at the 6 m line or the 9 m line.
  final double peakOpacity;

  /// Blur applied to the drawn cells, as a fraction of one cell's width.
  final double blurCells;

  const HeatmapLayer({
    required this.grid,
    required this.color,
    this.peakOpacity = 0.88,
    this.blurCells = 0.7,
  });

  /// Cells fainter than this are left unpainted.
  ///
  /// A cell holding a thousandth of the peak is one stray fix; drawing it
  /// spends fill rate on noise and, once blurred, smears a haze over the whole
  /// court that reads as "they were everywhere".
  static const double _minIntensity = 0.02;

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    if (grid.isEmpty) return;

    final courtRect = transform.worldRectToScreen(
      Rect.fromLTWH(0, 0, grid.widthMeters, grid.heightMeters),
    );
    final cellWidth = transform.metresToPixels(grid.cellWidthMeters);
    final cellHeight = transform.metresToPixels(grid.cellHeightMeters);
    final sigma = cellWidth * blurCells;

    canvas.save();
    canvas.clipRect(courtRect);

    // One blurred layer for the whole map. Blurring each cell on its own would
    // multiply the alpha wherever two blurs overlapped, turning a dense area
    // into a solid block rather than a bright one.
    canvas.saveLayer(
      courtRect,
      Paint()
        ..imageFilter =
            ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
    );

    final peakMicros = grid.peak.inMicroseconds;
    for (var row = 0; row < grid.rows; row++) {
      for (var column = 0; column < grid.columns; column++) {
        final intensity = grid.dwellMicrosAt(column, row) / peakMicros;
        if (intensity < _minIntensity) continue;

        final topLeft = transform.worldToScreen(
          Offset(column * grid.cellWidthMeters, row * grid.cellHeightMeters),
        );
        canvas.drawRect(
          // Half a pixel of overlap: adjacent cells of the same colour must
          // not show a seam where their antialiased edges meet.
          Rect.fromLTWH(topLeft.dx, topLeft.dy, cellWidth, cellHeight)
              .inflate(0.5),
          Paint()..color = heatShade(color, intensity, peakOpacity: peakOpacity),
        );
      }
    }

    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(HeatmapLayer oldLayer) =>
      !identical(oldLayer.grid, grid) ||
      oldLayer.color != color ||
      oldLayer.peakOpacity != peakOpacity ||
      oldLayer.blurCells != blurCells;
}

/// Rings the dwell-weighted average position on the court.
///
/// One point is a poor summary of a movement map and a good anchor for it: the
/// eye reads the heat as a shape, and the ring says where that shape's balance
/// actually sits. Drawn as an outline rather than as a filled marker so it
/// never hides the cell it stands on.
class AveragePositionLayer extends CourtLayer {
  final double xMeters;
  final double yMeters;

  /// Radius in logical pixels — a fixed size on screen, like the player
  /// markers, because it is an annotation rather than a thing on the floor.
  static const double radiusPixels = 9;

  /// Drawn in the court's own marking colour rather than in the map's, so it
  /// reads as part of the court furniture at every point of the ramp — a ring
  /// in the team colour would vanish into the heat it annotates.
  static const Color _ringColor = Color(0xFFF2F5F7);

  const AveragePositionLayer({required this.xMeters, required this.yMeters});

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    final centre = transform.worldToScreen(Offset(xMeters, yMeters));

    // A dark halo first, so the ring survives being drawn on the hottest part
    // of its own map.
    canvas.drawCircle(
      centre,
      radiusPixels,
      Paint()
        ..color = const Color(0xCC0C1015)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      centre,
      radiusPixels,
      Paint()
        ..color = _ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    canvas.drawCircle(centre, 1.8, Paint()..color = _ringColor);
  }

  @override
  bool shouldRepaint(AveragePositionLayer oldLayer) =>
      oldLayer.xMeters != xMeters || oldLayer.yMeters != yMeters;
}

/// The colour of a cell holding [intensity] of the busiest cell's time.
///
/// A sequential ramp in a single hue — [base]'s — because the value it encodes
/// is a magnitude: dwell time has an order, and two hues would invite the
/// reader to see two kinds of place instead of more and less of one thing.
///
/// Two channels move together along the ramp, both monotonically:
///
///  * **Alpha**, from nothing to [peakOpacity]. Near-zero has to recede into
///    the court rather than tint it, or an empty corner reads as lightly used.
///  * **Lightness**, upwards. The court is dark, so on it "more" must mean
///    brighter; a ramp that only moved alpha would leave the hot end and the
///    warm end the same colour at different strengths.
Color heatShade(Color base, double intensity, {double peakOpacity = 0.88}) {
  final t = intensity.clamp(0.0, 1.0);
  if (t <= 0) return base.withValues(alpha: 0);

  final hsl = HSLColor.fromColor(base);
  final shade = hsl
      // A washed-out team colour would make the ramp read as grey where it is
      // faintest, which is where the reader most needs to see the hue.
      .withSaturation(hsl.saturation.clamp(0.5, 1.0))
      .withLightness(lerpDouble(0.36, 0.74, t)!)
      .toColor();

  // The floor keeps a cell that was genuinely stood in from disappearing: the
  // difference between "briefly" and "never" is the whole point of the map's
  // outline.
  return shade.withValues(alpha: (0.12 + 0.88 * t) * peakOpacity);
}
