import 'package:flutter/material.dart';

/// Colours and stroke widths for court rendering.
///
/// Kept separate from the widget tree so that painters stay pure and so a
/// future light/dark or high-contrast variant is a single object swap rather
/// than edits scattered across painters.
@immutable
class CourtTheme {
  /// Area outside the playing court but inside the visible world.
  final Color surroundColor;

  /// The playing surface itself.
  final Color courtColor;

  /// The goal areas ("6 m" zones).
  final Color goalAreaColor;

  final Color lineColor;
  final Color goalColor;

  /// Stroke width of court markings, **in metres**.
  ///
  /// Real handball markings are 5 cm wide. Expressing the width in metres and
  /// scaling it with the transform means the court looks correct at any zoom
  /// instead of turning into hairlines or slabs.
  final double lineWidthMeters;

  /// Lower bound on marking width in logical pixels, so lines stay visible
  /// when the window is small.
  final double minLineWidthPixels;

  const CourtTheme({
    this.surroundColor = const Color(0xFF12161C),
    this.courtColor = const Color(0xFF1F6F4A),
    this.goalAreaColor = const Color(0xFF17573A),
    this.lineColor = const Color(0xFFF2F5F7),
    this.goalColor = const Color(0xFFE8B04B),
    this.lineWidthMeters = 0.05,
    this.minLineWidthPixels = 1.0,
  });

  /// Resolves the marking stroke width in logical pixels at [scale] px/m.
  double strokeWidth(double scale) =>
      (lineWidthMeters * scale).clamp(minLineWidthPixels, double.infinity);

  /// The court as a backdrop rather than as the subject.
  ///
  /// A heatmap is a colour scale drawn on top of the floor, and the playing
  /// green competes with it twice over: it is saturated enough to shift how
  /// the colours above it read, and bright enough that the faint end of a ramp
  /// disappears into it. This variant keeps every marking in place — a coach
  /// reads a heatmap against the 6 m and 9 m lines — while dropping the
  /// surface to a near-neutral dark and the lines to a whisper.
  static const CourtTheme analysis = CourtTheme(
    surroundColor: Color(0xFF12161C),
    courtColor: Color(0xFF141A19),
    goalAreaColor: Color(0xFF1A2321),
    lineColor: Color(0x66F2F5F7),
    goalColor: Color(0x99E8B04B),
  );
}
