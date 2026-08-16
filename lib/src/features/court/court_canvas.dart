import 'package:flutter/widgets.dart';

import '../../core/court_view_transform.dart';
import '../../domain/court.dart';
import 'court_layer.dart';

/// Renders a court and an ordered stack of [CourtLayer]s at real-world scale.
///
/// The canvas owns exactly one responsibility: turning the available box into
/// a [CourtViewTransform] and handing it to its layers. It knows nothing about
/// receivers, tags, recordings or playback, which is what lets setup, live,
/// replay and analysis all reuse it.
///
/// Callers that need to react to pointer input receive world coordinates via
/// [onWorldTapDown] and friends, never pixels — screen pixels must not leak
/// into domain logic.
class CourtCanvas extends StatelessWidget {
  final Court court;

  /// Layers painted in order, first at the back.
  final List<CourtLayer> layers;

  /// Extra world margin around the playing area, in metres, so that
  /// off-court receivers remain visible.
  final double marginMeters;

  /// Padding between the visible world and the widget edge, in pixels.
  final double paddingPixels;

  final void Function(Offset worldPosition)? onWorldTapDown;
  final void Function(Offset worldPosition)? onWorldPanStart;
  final void Function(Offset worldPosition)? onWorldPanUpdate;
  final VoidCallback? onWorldPanEnd;

  const CourtCanvas({
    super.key,
    required this.court,
    required this.layers,
    this.marginMeters = 5.0,
    this.paddingPixels = 12.0,
    this.onWorldTapDown,
    this.onWorldPanStart,
    this.onWorldPanUpdate,
    this.onWorldPanEnd,
  });

  /// The world region the canvas shows: the playing area plus [marginMeters]
  /// on every side.
  Rect visibleWorldFor(Court court) => Rect.fromLTRB(
        -marginMeters,
        -marginMeters,
        court.widthMeters + marginMeters,
        court.heightMeters + marginMeters,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A zero/unbounded box can occur during layout; fall back to a size
        // that keeps the transform well-defined.
        final size = Size(
          constraints.hasBoundedWidth && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 800,
          constraints.hasBoundedHeight && constraints.maxHeight > 0
              ? constraints.maxHeight
              : 400,
        );

        final transform = CourtViewTransform.fit(
          visibleWorld: visibleWorldFor(court),
          viewport: size,
          padding: paddingPixels,
        );

        Widget canvas = CustomPaint(
          size: size,
          painter: _CourtPainter(layers: layers, transform: transform),
          isComplex: true,
          willChange: true,
        );

        final wantsPointer = onWorldTapDown != null ||
            onWorldPanStart != null ||
            onWorldPanUpdate != null ||
            onWorldPanEnd != null;

        if (wantsPointer) {
          canvas = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onWorldTapDown == null
                ? null
                : (details) => onWorldTapDown!(
                    transform.screenToWorld(details.localPosition)),
            onPanStart: onWorldPanStart == null
                ? null
                : (details) => onWorldPanStart!(
                    transform.screenToWorld(details.localPosition)),
            onPanUpdate: onWorldPanUpdate == null
                ? null
                : (details) => onWorldPanUpdate!(
                    transform.screenToWorld(details.localPosition)),
            onPanEnd:
                onWorldPanEnd == null ? null : (_) => onWorldPanEnd!(),
            child: canvas,
          );
        }

        return canvas;
      },
    );
  }
}

class _CourtPainter extends CustomPainter {
  final List<CourtLayer> layers;
  final CourtViewTransform transform;

  const _CourtPainter({required this.layers, required this.transform});

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in layers) {
      canvas.save();
      layer.paint(canvas, transform);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CourtPainter oldDelegate) {
    if (oldDelegate.transform.scale != transform.scale ||
        oldDelegate.transform.originOnScreen != transform.originOnScreen) {
      return true;
    }
    if (oldDelegate.layers.length != layers.length) return true;

    for (var i = 0; i < layers.length; i++) {
      final old = oldDelegate.layers[i];
      final current = layers[i];
      if (old.runtimeType != current.runtimeType) return true;
      if (current.shouldRepaint(old)) return true;
    }
    return false;
  }
}
