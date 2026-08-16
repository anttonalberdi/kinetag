import 'package:meta/meta.dart';

/// The noise-rejection knobs `SessionMetrics` computes under.
///
/// Bundled into one immutable value rather than passed as loose parameters so
/// that a computed metric can always be paired with the thresholds it was
/// produced under. That matters because these are *interpretation*, not data:
/// the same recording yields a different distance under a different speed
/// ceiling, and a number whose thresholds are unknown cannot be compared with
/// another.
///
/// Lives in the analytics layer, not in the settings feature, so that the
/// arithmetic stays usable from a headless job with no UI and no providers.
@immutable
class AnalyticsThresholds {
  /// Steps implying more than this are treated as positioning noise and
  /// dropped.
  ///
  /// Elite sprinters peak near 12 m/s and handball players well below that, so
  /// a step implying more is a bad fix, not a fast player. Dropping such steps
  /// matters most for *distance*: a single 30 m glitch and back adds 60 m of
  /// phantom running to a player's total.
  final double maxPlausibleSpeedMps;

  /// Speeds are measured over at least this much time.
  ///
  /// Consecutive samples 50 ms apart are separated by centimetres, so position
  /// error of a few centimetres — routine for UWB — would dominate a
  /// sample-to-sample speed and make the maximum meaningless. Measuring over a
  /// window trades a little peak sharpness for a number that reflects the
  /// player rather than the noise.
  final Duration speedWindow;

  /// Samples whose positioning confidence is below this are ignored entirely.
  ///
  /// Zero by default: with a synthetic confidence the filter would only throw
  /// data away. It becomes useful with real hardware, where a fix computed
  /// from too few anchors reports low confidence and is exactly the sample
  /// worth excluding before it inflates a distance total.
  final double minConfidence;

  const AnalyticsThresholds({
    this.maxPlausibleSpeedMps = 12.0,
    this.speedWindow = const Duration(milliseconds: 200),
    this.minConfidence = 0.0,
  });

  static const AnalyticsThresholds defaults = AnalyticsThresholds();

  /// Bounds the settings UI offers, and the range the model is meaningful in.
  static const double minSpeedCeilingMps = 4.0;
  static const double maxSpeedCeilingMps = 25.0;
  static const Duration minSpeedWindow = Duration(milliseconds: 50);
  static const Duration maxSpeedWindow = Duration(milliseconds: 1000);

  AnalyticsThresholds copyWith({
    double? maxPlausibleSpeedMps,
    Duration? speedWindow,
    double? minConfidence,
  }) =>
      AnalyticsThresholds(
        maxPlausibleSpeedMps: maxPlausibleSpeedMps ?? this.maxPlausibleSpeedMps,
        speedWindow: speedWindow ?? this.speedWindow,
        minConfidence: minConfidence ?? this.minConfidence,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalyticsThresholds &&
          other.maxPlausibleSpeedMps == maxPlausibleSpeedMps &&
          other.speedWindow == speedWindow &&
          other.minConfidence == minConfidence;

  @override
  int get hashCode =>
      Object.hash(maxPlausibleSpeedMps, speedWindow, minConfidence);

  @override
  String toString() => 'AnalyticsThresholds('
      'max ${maxPlausibleSpeedMps.toStringAsFixed(1)} m/s, '
      'window ${speedWindow.inMilliseconds} ms, '
      'confidence >= ${minConfidence.toStringAsFixed(2)})';
}
