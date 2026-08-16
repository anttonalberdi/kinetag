import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A single computed position for one tag at one instant.
///
/// ## Why microseconds as `int`
///
/// Timestamps are stored as integer microseconds since the Unix epoch rather
/// than as floating-point seconds. At the target rate of 50–100 samples per
/// second per tag, consecutive samples are 10–20 ms apart. A `double` holding
/// seconds-since-epoch (~1.8e9) has only ~0.2 µs of resolution left in its
/// mantissa and accumulates rounding error, which shows up directly as noise
/// in derived velocity (`dx / dt`). Integer microseconds are exact.
@immutable
class PositionSample {
  /// Microseconds since the Unix epoch, UTC.
  final int timestampMicros;

  final String tagId;

  /// Position in real-world metres, in court coordinates.
  final double x;
  final double y;

  /// Positioning quality in the range 0..1, where 1 is best.
  ///
  /// For simulated data this is synthetic. For real UWB it will be derived
  /// from anchor geometry (GDOP), residuals and the number of contributing
  /// receivers.
  final double confidence;

  const PositionSample({
    required this.timestampMicros,
    required this.tagId,
    required this.x,
    required this.y,
    this.confidence = 1.0,
  });

  DateTime get timestamp =>
      DateTime.fromMicrosecondsSinceEpoch(timestampMicros, isUtc: true);

  /// Planar distance to [other] in metres, ignoring time.
  double distanceTo(PositionSample other) {
    final dx = other.x - x;
    final dy = other.y - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Average speed in metres per second between this sample and [other].
  ///
  /// Returns 0 when the two samples share a timestamp, rather than dividing
  /// by zero — duplicate timestamps are possible if hardware retransmits.
  double speedTo(PositionSample other) {
    final dtSeconds = (other.timestampMicros - timestampMicros) / 1e6;
    if (dtSeconds == 0) return 0;
    return distanceTo(other) / dtSeconds.abs();
  }

  PositionSample copyWith({
    int? timestampMicros,
    String? tagId,
    double? x,
    double? y,
    double? confidence,
  }) =>
      PositionSample(
        timestampMicros: timestampMicros ?? this.timestampMicros,
        tagId: tagId ?? this.tagId,
        x: x ?? this.x,
        y: y ?? this.y,
        confidence: confidence ?? this.confidence,
      );

  Map<String, dynamic> toJson() => {
        'timestampMicros': timestampMicros,
        'tagId': tagId,
        'x': x,
        'y': y,
        'confidence': confidence,
      };

  factory PositionSample.fromJson(Map<String, dynamic> json) => PositionSample(
        timestampMicros: json['timestampMicros'] as int,
        tagId: json['tagId'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionSample &&
          other.timestampMicros == timestampMicros &&
          other.tagId == tagId &&
          other.x == x &&
          other.y == y &&
          other.confidence == confidence;

  @override
  int get hashCode =>
      Object.hash(timestampMicros, tagId, x, y, confidence);

  @override
  String toString() => 'PositionSample($tagId @ ${x.toStringAsFixed(2)},'
      '${y.toStringAsFixed(2)} t=$timestampMicros)';
}
