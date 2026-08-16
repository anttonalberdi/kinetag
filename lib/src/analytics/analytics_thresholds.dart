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

/// The knobs that decide *when* a player was playing and *which way* their
/// team was playing at the time.
///
/// Separate from [AnalyticsThresholds] because the two answer different
/// questions and fail differently. Those settings reject bad measurements; the
/// ones here interpret good ones, turning positions into "on court", "on the
/// bench", "attacking" and "defending". A recording can be perfectly clean and
/// still be segmented wrongly, so the segmentation carries its own settings and
/// is reported with them, exactly as the movement figures are.
@immutable
class PlayThresholds {
  /// How far inside the lines a tag must be to count as having come on, in
  /// metres.
  ///
  /// Together with [offCourtMarginMeters] this is a hysteresis band: a player
  /// standing on the sideline does not flicker between playing and benched
  /// every time positioning noise moves them a few centimetres, because
  /// leaving requires crossing a different, further line than entering did.
  final double onCourtInsetMeters;

  /// How far outside the lines a tag must be to count as having left, in
  /// metres.
  final double offCourtMarginMeters;

  /// The shortest on-court or bench spell that is believed.
  ///
  /// Ten seconds is chosen against the sport, not against the noise: no real
  /// substitution puts a player on for less, and no legitimate reason to be
  /// off the court during play — a throw-in taken from behind the line, a
  /// player stumbling over it — lasts longer. Anything shorter is absorbed
  /// into the spell before it, so a corner throw is not recorded as a
  /// substitution and back again.
  final Duration minStint;

  /// How long the goalkeeper signal is averaged over before a phase is called.
  ///
  /// A keeper drifts around their line for reasons that have nothing to do
  /// with where the ball is, and that drift is the same size as the signal
  /// being measured. Averaging over seconds removes it; a handball possession
  /// lasts far longer than this window, so almost none of the real signal goes
  /// with it.
  final Duration possessionWindow;

  /// How far the smoothed keeper signal must move off centre before a phase is
  /// called, in metres.
  ///
  /// In metres rather than as a fraction of the court because a keeper's step
  /// off the goal line is an absolute distance — the same on a full court as
  /// on a training pitch.
  final double possessionMarginMeters;

  /// The shortest possession that is believed, for the same reason
  /// [minStint] exists.
  final Duration minPossession;

  const PlayThresholds({
    this.onCourtInsetMeters = 0.10,
    this.offCourtMarginMeters = 0.30,
    this.minStint = const Duration(seconds: 10),
    this.possessionWindow = const Duration(seconds: 5),
    this.possessionMarginMeters = 0.5,
    this.minPossession = const Duration(seconds: 6),
  });

  static const PlayThresholds defaults = PlayThresholds();

  PlayThresholds copyWith({
    double? onCourtInsetMeters,
    double? offCourtMarginMeters,
    Duration? minStint,
    Duration? possessionWindow,
    double? possessionMarginMeters,
    Duration? minPossession,
  }) =>
      PlayThresholds(
        onCourtInsetMeters: onCourtInsetMeters ?? this.onCourtInsetMeters,
        offCourtMarginMeters: offCourtMarginMeters ?? this.offCourtMarginMeters,
        minStint: minStint ?? this.minStint,
        possessionWindow: possessionWindow ?? this.possessionWindow,
        possessionMarginMeters:
            possessionMarginMeters ?? this.possessionMarginMeters,
        minPossession: minPossession ?? this.minPossession,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayThresholds &&
          other.onCourtInsetMeters == onCourtInsetMeters &&
          other.offCourtMarginMeters == offCourtMarginMeters &&
          other.minStint == minStint &&
          other.possessionWindow == possessionWindow &&
          other.possessionMarginMeters == possessionMarginMeters &&
          other.minPossession == minPossession;

  @override
  int get hashCode => Object.hash(
        onCourtInsetMeters,
        offCourtMarginMeters,
        minStint,
        possessionWindow,
        possessionMarginMeters,
        minPossession,
      );

  @override
  String toString() => 'PlayThresholds('
      'stints >= ${minStint.inSeconds} s, '
      'keeper window ${possessionWindow.inSeconds} s, '
      'margin ${possessionMarginMeters.toStringAsFixed(2)} m)';
}
