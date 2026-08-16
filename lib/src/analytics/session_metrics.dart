import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../domain/domain.dart';

/// Movement metrics for one tag's trajectory.
///
/// Derived, never stored (decision 6): stored samples are the single source
/// of truth, and every number here is recomputed from them. Persisting these
/// would guarantee that an improved positioning algorithm — or a corrected
/// outlier rule — leaves stale figures behind in the database.
@immutable
class PlayerTrackMetrics {
  final String tagId;

  /// Path length in metres: the sum of the steps between samples.
  final double distanceMeters;

  /// Fastest windowed speed observed, in metres per second.
  final double maxSpeedMps;

  /// Distance divided by the tracked span.
  ///
  /// This is mean speed over the whole recording, standing still included —
  /// not mean speed while moving. That makes it comparable between players
  /// in the same session and useless for comparing a bench player with a
  /// starter, which is the honest limit of a single number.
  final double averageSpeedMps;

  /// Time between the first and last sample for this tag.
  final Duration trackedDuration;

  final int sampleCount;

  /// Steps rejected as physically impossible — see
  /// [SessionMetrics.maxPlausibleSpeedMps]. A non-zero count on real hardware
  /// means positioning noise, not a fast player.
  final int discardedSteps;

  /// Windowed speed series, as parallel arrays in ascending time order.
  ///
  /// Two lists rather than a list of objects: one entry per sample per tag is
  /// the largest thing analytics allocates, and at 30 tags x 100 Hz the
  /// difference between packed doubles and a boxed object each is real.
  /// Read them through [speedAt].
  final List<int> speedTimesMicros;
  final List<double> speeds;

  const PlayerTrackMetrics({
    required this.tagId,
    required this.distanceMeters,
    required this.maxSpeedMps,
    required this.averageSpeedMps,
    required this.trackedDuration,
    required this.sampleCount,
    required this.discardedSteps,
    required this.speedTimesMicros,
    required this.speeds,
  });

  /// Instantaneous speed in force at [timestampMicros], in m/s.
  ///
  /// Returns the most recent speed at or before that instant, which is what
  /// a replay playhead needs; 0 before the first one.
  double speedAt(int timestampMicros) {
    if (speeds.isEmpty) return 0;

    var low = 0;
    var high = speedTimesMicros.length - 1;
    var best = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (speedTimesMicros[mid] <= timestampMicros) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best < 0 ? 0 : speeds[best];
  }

  @override
  String toString() => 'PlayerTrackMetrics($tagId, '
      '${distanceMeters.toStringAsFixed(1)} m, '
      'max ${maxSpeedMps.toStringAsFixed(1)} m/s)';
}

/// Per-player movement metrics for one recording.
///
/// Pure Dart and synchronous: no Flutter, no storage, no providers, so the
/// arithmetic can be tested against hand-computed trajectories and reused
/// from a future export or headless analysis job.
@immutable
class SessionMetrics {
  final Map<String, PlayerTrackMetrics> byTagId;

  const SessionMetrics(this.byTagId);

  /// Speeds above this are treated as positioning noise rather than
  /// movement, and the step is dropped.
  ///
  /// Elite sprinters peak near 12 m/s and handball players well below that,
  /// so a step implying more is a bad fix, not a fast player. Dropping such
  /// steps matters most for *distance*: a single 30 m glitch and back adds
  /// 60 m of phantom running to a player's total.
  static const double maxPlausibleSpeedMps = 12.0;

  /// Speeds are measured over at least this much time.
  ///
  /// Consecutive samples 50 ms apart are separated by centimetres, so
  /// position error of a few centimetres — routine for UWB — would dominate
  /// a sample-to-sample speed and make the maximum meaningless. Measuring
  /// over a window trades a little peak sharpness for a number that reflects
  /// the player rather than the noise.
  static const Duration speedWindow = Duration(milliseconds: 200);

  /// Computes metrics from a flat, time-ordered list of samples.
  factory SessionMetrics.fromSamples(Iterable<PositionSample> samples) {
    final byTag = <String, List<PositionSample>>{};
    for (final sample in samples) {
      (byTag[sample.tagId] ??= []).add(sample);
    }

    return SessionMetrics({
      for (final entry in byTag.entries)
        entry.key: _metricsForTrack(entry.key, entry.value),
    });
  }

  /// Computes metrics from frames, the shape replay already holds.
  factory SessionMetrics.fromFrames(Iterable<PositionFrame> frames) =>
      SessionMetrics.fromSamples([
        for (final frame in frames) ...frame.samples,
      ]);

  PlayerTrackMetrics? forTag(String tagId) => byTagId[tagId];

  /// Tracks ordered by distance covered, farthest first.
  List<PlayerTrackMetrics> get byDistance {
    final all = byTagId.values.toList()
      ..sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters));
    return all;
  }

  double get totalDistanceMeters =>
      byTagId.values.fold(0.0, (sum, m) => sum + m.distanceMeters);

  bool get isEmpty => byTagId.isEmpty;

  static PlayerTrackMetrics _metricsForTrack(
    String tagId,
    List<PositionSample> track,
  ) {
    track.sort((a, b) => a.timestampMicros.compareTo(b.timestampMicros));

    var distance = 0.0;
    var discarded = 0;

    // Path length, one step at a time. A step to an implausible position is
    // dropped and the previous *accepted* sample is kept as the anchor, so
    // the next step bridges the glitch instead of losing the real movement
    // that happened across it.
    var previous = 0;
    for (var i = 1; i < track.length; i++) {
      final dtSeconds =
          (track[i].timestampMicros - track[previous].timestampMicros) / 1e6;
      if (dtSeconds <= 0) continue;

      final step = track[previous].distanceTo(track[i]);
      if (step / dtSeconds > maxPlausibleSpeedMps) {
        discarded++;
        continue;
      }
      distance += step;
      previous = i;
    }

    // Windowed speeds: straight-line displacement from the newest sample at
    // least [speedWindow] old. `window` only ever moves forward, so the pass
    // is linear rather than quadratic.
    //
    // Samples in the first window have no full window behind them and are
    // skipped rather than measured over a shorter one — a short baseline is
    // exactly the noisy measurement the window exists to avoid.
    final speedTimes = <int>[];
    final speeds = <double>[];
    var maxSpeed = 0.0;
    var window = 0;

    for (var i = 1; i < track.length; i++) {
      while (window + 1 < i &&
          track[i].timestampMicros - track[window + 1].timestampMicros >=
              speedWindow.inMicroseconds) {
        window++;
      }

      final dtMicros =
          track[i].timestampMicros - track[window].timestampMicros;
      if (dtMicros < speedWindow.inMicroseconds) continue;

      final speed = track[window].distanceTo(track[i]) / (dtMicros / 1e6);
      if (speed > maxPlausibleSpeedMps) continue;

      speedTimes.add(track[i].timestampMicros);
      speeds.add(speed);
      maxSpeed = math.max(maxSpeed, speed);
    }

    final trackedMicros = track.length < 2
        ? 0
        : track.last.timestampMicros - track.first.timestampMicros;
    final averageSpeed =
        trackedMicros <= 0 ? 0.0 : distance / (trackedMicros / 1e6);

    return PlayerTrackMetrics(
      tagId: tagId,
      distanceMeters: distance,
      maxSpeedMps: maxSpeed,
      averageSpeedMps: averageSpeed,
      trackedDuration: Duration(microseconds: trackedMicros),
      sampleCount: track.length,
      discardedSteps: discarded,
      speedTimesMicros: speedTimes,
      speeds: speeds,
    );
  }
}
