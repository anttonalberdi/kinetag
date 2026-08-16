import 'package:flutter/painting.dart';

import '../../core/court_view_transform.dart';
import '../../domain/receiver.dart';
import '../court/court_layer.dart';

/// Draws receivers, their labels, and the selection highlight.
///
/// Marker sizes are expressed in **logical pixels**, not metres: a receiver is
/// a UI affordance to be clicked, so it must stay a constant, comfortable
/// target size regardless of how far the court is zoomed. Its *position*
/// remains pure world metres.
class ReceiverLayer extends CourtLayer {
  final List<Receiver> receivers;
  final String? selectedReceiverId;

  /// Radius of a receiver marker, in logical pixels.
  static const double markerRadiusPixels = 9.0;

  /// Extra slack around the marker when hit-testing, in logical pixels.
  static const double hitPaddingPixels = 6.0;

  /// Radius a pointer must fall within to select a receiver, in pixels.
  static const double hitRadiusPixels =
      markerRadiusPixels + hitPaddingPixels;

  final Color color;
  final Color selectedColor;
  final Color labelColor;

  const ReceiverLayer({
    required this.receivers,
    this.selectedReceiverId,
    this.color = const Color(0xFF62B6FF),
    this.selectedColor = const Color(0xFFFFC24B),
    this.labelColor = const Color(0xFFE9EEF3),
  });

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    for (final receiver in receivers) {
      final isSelected = receiver.id == selectedReceiverId;
      final centre = transform.worldToScreen(Offset(receiver.x, receiver.y));

      if (isSelected) _paintSelectionHalo(canvas, centre);
      _paintMarker(canvas, centre, isSelected);
      _paintLabel(canvas, centre, receiver, isSelected);
    }
  }

  void _paintSelectionHalo(Canvas canvas, Offset centre) {
    canvas.drawCircle(
      centre,
      markerRadiusPixels + 7,
      Paint()..color = selectedColor.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      centre,
      markerRadiusPixels + 7,
      Paint()
        ..color = selectedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintMarker(Canvas canvas, Offset centre, bool isSelected) {
    final fill = isSelected ? selectedColor : color;

    canvas.drawCircle(
      centre,
      markerRadiusPixels,
      Paint()..color = fill,
    );
    canvas.drawCircle(
      centre,
      markerRadiusPixels,
      Paint()
        ..color = const Color(0xFF0C1015)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // A small inner dot marks the exact world coordinate, so the operator can
    // see precisely which point the numeric X/Y refer to.
    canvas.drawCircle(
      centre,
      2.0,
      Paint()..color = const Color(0xFF0C1015),
    );
  }

  void _paintLabel(
    Canvas canvas,
    Offset centre,
    Receiver receiver,
    bool isSelected,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: receiver.name,
        style: TextStyle(
          color: isSelected ? selectedColor : labelColor,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final origin = Offset(
      centre.dx - painter.width / 2,
      centre.dy + markerRadiusPixels + 6,
    );

    // Backing plate keeps the label readable over court markings.
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        origin.dx - 4,
        origin.dy - 2,
        painter.width + 8,
        painter.height + 4,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      plate,
      Paint()..color = const Color(0xCC0C1015),
    );

    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(ReceiverLayer oldLayer) =>
      oldLayer.selectedReceiverId != selectedReceiverId ||
      !_sameReceivers(oldLayer.receivers, receivers);

  static bool _sameReceivers(List<Receiver> a, List<Receiver> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Draws dashed baselines from the selected receiver to all the others.
///
/// Makes the anchor geometry legible at a glance while positions are being
/// adjusted — the numbers live in the inspector, this is the spatial view.
class ReceiverBaselineLayer extends CourtLayer {
  final List<Receiver> receivers;
  final String? selectedReceiverId;
  final Color color;

  const ReceiverBaselineLayer({
    required this.receivers,
    this.selectedReceiverId,
    this.color = const Color(0x66FFC24B),
  });

  @override
  void paint(Canvas canvas, CourtViewTransform transform) {
    if (selectedReceiverId == null) return;

    Receiver? origin;
    for (final r in receivers) {
      if (r.id == selectedReceiverId) origin = r;
    }
    if (origin == null) return;

    final from = transform.worldToScreen(Offset(origin.x, origin.y));
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final r in receivers) {
      if (r.id == origin.id) continue;
      final to = transform.worldToScreen(Offset(r.x, r.y));
      _drawDashedLine(canvas, from, to, paint);
    }
  }

  static void _drawDashedLine(
      Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    final total = (to - from).distance;
    if (total == 0) return;

    final direction = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(ReceiverBaselineLayer oldLayer) =>
      oldLayer.selectedReceiverId != selectedReceiverId ||
      oldLayer.receivers != receivers;
}
