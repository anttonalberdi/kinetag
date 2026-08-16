import 'package:flutter/widgets.dart';

import '../../core/court_view_transform.dart';
import '../../domain/court.dart';
import 'court_layer.dart';

/// Reports a pointer position in world metres, with the transform that
/// produced it.
typedef CourtPointerCallback = void Function(
  Offset worldPosition,
  CourtViewTransform transform,
);

/// Reports the start of a drag at the position where the pointer actually
/// went **down**, in world metres.
///
/// This is deliberately not the position `onPanStart` supplies. Flutter only
/// recognises a pan once the 18 px touch slop is exceeded, so by the time
/// `onPanStart` fires the pointer has already travelled — further than the
/// ~15 px radius of a receiver marker. Hit-testing against that displaced
/// point would fail to grab small targets, and anchoring a grab offset there
/// would leave the dragged object trailing the cursor by the slop distance
/// for the rest of the gesture.
typedef CourtDragStartCallback = void Function(
  Offset pointerDownWorld,
  CourtViewTransform transform,
);

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
class CourtCanvas extends StatefulWidget {
  final Court court;

  /// Layers painted in order, first at the back.
  final List<CourtLayer> layers;

  /// Extra world margin around the playing area, in metres, so that
  /// off-court receivers remain visible.
  final double marginMeters;

  /// Padding between the visible world and the widget edge, in pixels.
  final double paddingPixels;

  /// Pointer callbacks report **world metres**, never pixels.
  ///
  /// The active [CourtViewTransform] is supplied alongside so that callers
  /// can express a hit-test tolerance in screen pixels (a fingertip is a
  /// fixed pixel size, not a fixed number of metres) and convert it to metres
  /// themselves. Domain state still only ever sees metres.
  final CourtPointerCallback? onWorldTapDown;
  final CourtDragStartCallback? onWorldPanStart;
  final CourtPointerCallback? onWorldPanUpdate;
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
  State<CourtCanvas> createState() => _CourtCanvasState();
}

class _CourtCanvasState extends State<CourtCanvas> {
  /// Local position of the most recent pointer-down.
  ///
  /// Captured through a [Listener], which fires before gesture recognition,
  /// so it records where the pointer genuinely landed rather than where the
  /// pan was eventually recognised.
  Offset? _pointerDownLocal;

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;

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
          visibleWorld: widget.visibleWorldFor(widget.court),
          viewport: size,
          padding: widget.paddingPixels,
        );

        Widget canvas = CustomPaint(
          size: size,
          painter:
              _CourtPainter(layers: widget.layers, transform: transform),
          isComplex: true,
          willChange: true,
        );

        final wantsPointer = widget.onWorldTapDown != null ||
            widget.onWorldPanStart != null ||
            widget.onWorldPanUpdate != null ||
            widget.onWorldPanEnd != null;

        if (wantsPointer) {
          canvas = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.onWorldTapDown == null
                ? null
                : (details) => widget.onWorldTapDown!(
                    transform.screenToWorld(details.localPosition), transform),
            onPanStart: widget.onWorldPanStart == null
                ? null
                : (details) {
                    // Use the recorded pointer-down point, falling back to
                    // the pan-start point if none was captured.
                    final down = _pointerDownLocal ?? details.localPosition;
                    widget.onWorldPanStart!(
                      transform.screenToWorld(down),
                      transform,
                    );
                  },
            onPanUpdate: widget.onWorldPanUpdate == null
                ? null
                : (details) => widget.onWorldPanUpdate!(
                    transform.screenToWorld(details.localPosition), transform),
            onPanEnd: widget.onWorldPanEnd == null
                ? null
                : (_) => widget.onWorldPanEnd!(),
            child: canvas,
          );

          canvas = Listener(
            behavior: HitTestBehavior.deferToChild,
            onPointerDown: (event) => _pointerDownLocal = event.localPosition,
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
