import 'package:flutter/painting.dart';

import '../../core/court_view_transform.dart';
import '../../domain/position_frame.dart';
import 'court_layer.dart';
import 'tag_roster.dart';

/// Draws the tracked players of a single [PositionFrame].
///
/// Like `ReceiverLayer`, marker geometry is in logical pixels while positions
/// stay in world metres: a player marker must remain legible whatever the
/// zoom, but must sit exactly where the tag says it is.
///
/// The layer holds a frame, not a stream. Everything that varies per frame —
/// which tags exist, what they are called, what colour they take — is
/// resolved once in [TagRoster]; painting is then a lookup and a few draw
/// calls per tag, with no allocation of text layouts on the render path.
class PlayerLayer extends CourtLayer {
  /// The frame to draw, or null before the first one arrives.
  final PositionFrame? frame;

  final TagRoster roster;

  /// Radius of a player marker, in logical pixels.
  static const double markerRadiusPixels = 11.0;

  /// Outline colour, matching the court's dark surround.
  static const Color outlineColor = Color(0xFF0C1015);

  const PlayerLayer({required this.frame, required this.roster});

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    final frame = this.frame;
    if (frame == null) return;

    for (final sample in frame.samples) {
      final entry = roster.entryFor(sample.tagId);
      final centre = transform.worldToScreen(Offset(sample.x, sample.y));
      final color = entry?.color ?? TagRoster.unassignedColor;

      canvas.drawCircle(
        centre,
        markerRadiusPixels,
        Paint()..color = color,
      );
      canvas.drawCircle(
        centre,
        markerRadiusPixels,
        Paint()
          ..color = outlineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final painter = entry?.labelPainter;
      if (painter != null) {
        painter.paint(
          canvas,
          centre - Offset(painter.width / 2, painter.height / 2),
        );
      }
    }
  }

  /// Repaints when the frame instant changes.
  ///
  /// Comparing timestamps rather than sample lists is both cheaper and
  /// stricter than it looks: frames are immutable and every frame carries a
  /// distinct instant, so equal timestamps mean identical content.
  @override
  bool shouldRepaint(PlayerLayer oldLayer) =>
      oldLayer.frame?.timestampMicros != frame?.timestampMicros ||
      !identical(oldLayer.roster, roster);
}
