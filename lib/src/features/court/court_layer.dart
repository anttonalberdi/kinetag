import 'package:flutter/rendering.dart';

import '../../core/court_view_transform.dart';

/// One drawable layer of a [CourtCanvas], painted in world coordinates.
///
/// Layers are how the same canvas serves setup, live, replay and analysis
/// without any of those screens owning a renderer of its own. Each screen
/// composes the layers it needs — court + receivers for setup, court + tags
/// for live, court + tags + trails for replay — and new visualisations
/// (heatmaps, vectors, polygons) arrive as additional layers rather than as
/// changes to existing ones.
///
/// Implementations receive a [CourtViewTransform] and are expected to convert
/// their own world-space geometry to screen space through it, never to assume
/// a pixel scale.
abstract class CourtLayer {
  const CourtLayer();

  void paint(Canvas canvas, CourtViewTransform transform);

  /// Whether this layer must be repainted given the [oldLayer] it replaces.
  ///
  /// Called only when the two layers have the same runtime type.
  bool shouldRepaint(covariant CourtLayer oldLayer) => true;
}
