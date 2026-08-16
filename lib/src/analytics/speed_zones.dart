import 'package:meta/meta.dart';

import 'session_metrics.dart';

/// Intensity bands a movement track is split into.
///
/// The bounds are indicative for indoor team sport rather than physiological
/// truth: without a player's own maximum speed, any absolute band is a
/// convention. They are stated here in one place so a reader can see exactly
/// what "sprinting" means in this app, and so the day a per-player maximum
/// exists there is a single thing to replace.
enum SpeedZone {
  standing('Standing', 0.0),
  walking('Walking', 0.6),
  jogging('Jogging', 2.0),
  running('Running', 4.0),
  sprinting('Sprinting', 5.5);

  /// Inclusive lower bound, in metres per second.
  final double lowerBoundMps;
  final String label;

  const SpeedZone(this.label, this.lowerBoundMps);

  /// The band [metresPerSecond] falls in. Negative speeds cannot occur, and
  /// would read as standing.
  static SpeedZone forSpeed(double metresPerSecond) {
    var zone = SpeedZone.standing;
    for (final candidate in SpeedZone.values) {
      if (metresPerSecond >= candidate.lowerBoundMps) zone = candidate;
    }
    return zone;
  }
}

/// How long one player spent in each intensity band.
///
/// Derived from the windowed speed series in [PlayerTrackMetrics], so it
/// inherits that series' noise rejection: a band can never be filled by a
/// speed the metrics themselves rejected as a bad fix.
@immutable
class SpeedZoneBreakdown {
  final Map<SpeedZone, Duration> byZone;

  const SpeedZoneBreakdown(this.byZone);

  /// A gap longer than this is assumed to be a dropout rather than time the
  /// player spent at the speed measured after it.
  ///
  /// Without the cap, a tag that goes silent for a minute would credit that
  /// whole minute to whichever band it reappeared in — the one figure most
  /// likely to be read as a training load.
  static const Duration maxAttributableGap = Duration(seconds: 1);

  /// Splits a track's speed series into bands.
  ///
  /// Each speed is credited with the time since the previous one, which makes
  /// the bands sum to the measured span rather than to a sample count — the
  /// distinction that matters when sampling is uneven.
  factory SpeedZoneBreakdown.fromTrack(PlayerTrackMetrics track) {
    final micros = <SpeedZone, int>{};
    final capMicros = maxAttributableGap.inMicroseconds;

    for (var i = 1; i < track.speeds.length; i++) {
      final gap = track.speedTimesMicros[i] - track.speedTimesMicros[i - 1];
      if (gap <= 0) continue;
      final zone = SpeedZone.forSpeed(track.speeds[i]);
      micros[zone] = (micros[zone] ?? 0) + (gap > capMicros ? capMicros : gap);
    }

    return SpeedZoneBreakdown({
      for (final entry in micros.entries)
        entry.key: Duration(microseconds: entry.value),
    });
  }

  /// The bands of several players added together, for a team total.
  factory SpeedZoneBreakdown.merged(Iterable<SpeedZoneBreakdown> parts) {
    final micros = <SpeedZone, int>{};
    for (final part in parts) {
      for (final entry in part.byZone.entries) {
        micros[entry.key] =
            (micros[entry.key] ?? 0) + entry.value.inMicroseconds;
      }
    }
    return SpeedZoneBreakdown({
      for (final entry in micros.entries)
        entry.key: Duration(microseconds: entry.value),
    });
  }

  Duration inZone(SpeedZone zone) => byZone[zone] ?? Duration.zero;

  Duration get total => byZone.values
      .fold(Duration.zero, (sum, duration) => sum + duration);

  /// Fraction of the measured time spent in [zone], in 0..1.
  double shareOf(SpeedZone zone) {
    final totalMicros = total.inMicroseconds;
    if (totalMicros <= 0) return 0;
    return inZone(zone).inMicroseconds / totalMicros;
  }

  bool get isEmpty => total == Duration.zero;
}
