import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// Bidirectional mapping between real-world court coordinates (metres) and
/// screen coordinates (logical pixels).
///
/// ## Coordinate conventions
///
/// World coordinates are metres. For a handball court the playing area spans
/// `(0,0)` at the top-left corner to `(40,20)` at the bottom-right corner:
///
/// ```
/// (0,0) ---------------------- (40,0)
///   |                             |
///   |                             | 20 m
/// (0,20) --------------------- (40,20)
///              40 m
/// ```
///
/// Note that **world +Y points down**, matching Flutter's screen convention.
/// This deliberately avoids a Y-flip in the transform. When real UWB hardware
/// arrives, its positioning output must be adapted to this convention at the
/// tracking-source boundary rather than here, so that every consumer of world
/// coordinates in the app agrees on orientation.
///
/// ## Fit behaviour
///
/// [visibleWorld] is the region that must be visible — typically larger than
/// the playing area so that receivers placed outside the court remain on
/// screen (e.g. x from -5..45, y from -5..25). It is scaled uniformly (one
/// scale factor for both axes, so the court never appears stretched) to fit
/// inside [viewport], then centred. A uniform scale is essential: an
/// anisotropic fit would make distances and speeds read differently along X
/// than along Y.
///
/// Because the transform is derived purely from [visibleWorld] and
/// [viewport], the same physical point maps to the same world coordinate
/// regardless of window size — resizing changes only how many pixels
/// represent one metre.
@immutable
class CourtViewTransform {
  /// The world region guaranteed to be visible, in metres.
  final Rect visibleWorld;

  /// The available drawing area, in logical pixels.
  final Size viewport;

  /// Logical pixels per metre. Uniform across both axes.
  final double scale;

  /// Screen-space offset of world origin `(0,0)`, in logical pixels.
  final Offset originOnScreen;

  const CourtViewTransform._({
    required this.visibleWorld,
    required this.viewport,
    required this.scale,
    required this.originOnScreen,
  });

  /// Builds a transform that fits [visibleWorld] inside [viewport], centred,
  /// with optional uniform [padding] in logical pixels.
  factory CourtViewTransform.fit({
    required Rect visibleWorld,
    required Size viewport,
    double padding = 0,
  }) {
    assert(visibleWorld.width > 0 && visibleWorld.height > 0,
        'visibleWorld must have positive extent');

    // Guard against a viewport smaller than its own padding, which would
    // otherwise yield a negative scale and mirror the whole scene.
    final availableWidth = (viewport.width - 2 * padding).clamp(1.0, double.infinity);
    final availableHeight = (viewport.height - 2 * padding).clamp(1.0, double.infinity);

    final scale = math.min(
      availableWidth / visibleWorld.width,
      availableHeight / visibleWorld.height,
    );

    // Centre the scaled world region inside the full viewport.
    final scaledWidth = visibleWorld.width * scale;
    final scaledHeight = visibleWorld.height * scale;
    final left = (viewport.width - scaledWidth) / 2;
    final top = (viewport.height - scaledHeight) / 2;

    // Screen position of world (0,0): start at the top-left of the drawn
    // region, then step back by where visibleWorld's own origin sits.
    final originOnScreen = Offset(
      left - visibleWorld.left * scale,
      top - visibleWorld.top * scale,
    );

    return CourtViewTransform._(
      visibleWorld: visibleWorld,
      viewport: viewport,
      scale: scale,
      originOnScreen: originOnScreen,
    );
  }

  /// Converts a world point in metres to screen logical pixels.
  Offset worldToScreen(Offset worldMetres) => Offset(
        originOnScreen.dx + worldMetres.dx * scale,
        originOnScreen.dy + worldMetres.dy * scale,
      );

  /// Converts a screen point in logical pixels back to world metres.
  ///
  /// Exact inverse of [worldToScreen] up to floating-point rounding.
  Offset screenToWorld(Offset screenPixels) => Offset(
        (screenPixels.dx - originOnScreen.dx) / scale,
        (screenPixels.dy - originOnScreen.dy) / scale,
      );

  /// Converts a length in metres to a length in logical pixels.
  double metresToPixels(double metres) => metres * scale;

  /// Converts a length in logical pixels to a length in metres.
  double pixelsToMetres(double pixels) => pixels / scale;

  /// Maps a world-space rectangle to its screen-space equivalent.
  Rect worldRectToScreen(Rect worldRect) => Rect.fromPoints(
        worldToScreen(worldRect.topLeft),
        worldToScreen(worldRect.bottomRight),
      );
}
