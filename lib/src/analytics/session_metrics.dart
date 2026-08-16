import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../domain/domain.dart';
import 'analytics_thresholds.dart';

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
  /// This is mean speed over the measured time, standing still included — not
  /// mean speed while moving. Which time is "measured" depends on what these
  /// metrics cover: over a whole recording it includes the bench, and over the
  /// on-court spells alone it does not. That is exactly why the split matters,
  /// and why a figure computed over everything cannot fairly compare a
  /// substitute with a starter.
  final double averageSpeedMps;

  /// Time covered by these metrics.
  ///
  /// For a single stretch of track that is the span from its first sample to
  /// its last. For metrics [merged] from several stretches — the on-court
  /// spells of a rotating player, say — it is the sum of those spans, and so
  /// counts only the time the player was actually being measured.
  final Duration trackedDuration;

  final int sampleCount;

  /// Steps rejected as physically impossible — see
  /// [AnalyticsThresholds.maxPlausibleSpeedMps]. A non-zero count on real
  /// hardware means positioning noise, not a fast player.
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

  /// Metrics covering no time at all, for a tag that was never in the split
  /// being measured — a player who never left the bench, or a team that never
  /// attacked while this one was on court.
  factory PlayerTrackMetrics.empty(String tagId) => PlayerTrackMetrics(
        tagId: tagId,
        distanceMeters: 0,
        maxSpeedMps: 0,
        averageSpeedMps: 0,
        trackedDuration: Duration.zero,
        sampleCount: 0,
        discardedSteps: 0,
        speedTimesMicros: const [],
        speeds: const [],
      );

  /// Several disjoint stretches of one tag's track, added together.
  ///
  /// This is what makes a statistic scoped to *when* rather than to the whole
  /// recording: a player's on-court metrics are the metrics of their stints
  /// merged, and their attacking metrics are the metrics of the parts of those
  /// stints their team spent attacking.
  ///
  /// Only the sums are meaningful to add; the rest are recombined as their
  /// meaning requires. Distance and measured time add, the maximum is the
  /// largest of the maxima, and average speed is recomputed from the two sums
  /// rather than averaged — averaging averages would weigh a ten-second stint
  /// as heavily as a ten-minute one.
  ///
  /// [parts] must be in time order, which they are by construction: they come
  /// from an interval list that is itself ordered.
  factory PlayerTrackMetrics.merged(
    String tagId,
    Iterable<PlayerTrackMetrics> parts,
  ) {
    var distance = 0.0;
    var maxSpeed = 0.0;
    var micros = 0;
    var samples = 0;
    var discarded = 0;
    final speedTimes = <int>[];
    final speeds = <double>[];

    for (final part in parts) {
      distance += part.distanceMeters;
      maxSpeed = math.max(maxSpeed, part.maxSpeedMps);
      micros += part.trackedDuration.inMicroseconds;
      samples += part.sampleCount;
      discarded += part.discardedSteps;
      speedTimes.addAll(part.speedTimesMicros);
      speeds.addAll(part.speeds);
    }

    return PlayerTrackMetrics(
      tagId: tagId,
      distanceMeters: distance,
      maxSpeedMps: maxSpeed,
      averageSpeedMps: micros <= 0 ? 0.0 : distance / (micros / 1e6),
      trackedDuration: Duration(microseconds: micros),
      sampleCount: samples,
      discardedSteps: discarded,
      speedTimesMicros: speedTimes,
      speeds: speeds,
    );
  }

  /// Whether any time at all was measured.
  bool get isEmpty => sampleCount == 0;

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

  /// The noise-rejection settings these figures were computed under.
  ///
  /// Carried with the result rather than left implicit, so a reader can tell
  /// whether two sets of numbers are comparable.
  final AnalyticsThresholds thresholds;

  const SessionMetrics(
    this.byTagId, {
    this.thresholds = AnalyticsThresholds.defaults,
  });

  /// Computes metrics from a flat, time-ordered list of samples.
  factory SessionMetrics.fromSamples(
    Iterable<PositionSample> samples, {
    AnalyticsThresholds thresholds = AnalyticsThresholds.defaults,
  }) {
    final byTag = groupByTag(samples, thresholds: thresholds);

    return SessionMetrics(
      {
        for (final entry in byTag.entries)
          entry.key: forTrack(entry.key, entry.value, thresholds: thresholds),
      },
      thresholds: thresholds,
    );
  }

  /// Splits [samples] per tag, dropping the ones no figure should be derived
  /// from and sorting what remains into time order.
  ///
  /// Public because every analysis that goes beyond a single number — where
  /// the time was spent, when a player was on court, which way their team was
  /// playing — starts from the same per-tag tracks, and each of them redoing
  /// the grouping would mean walking the largest list in the app several times
  /// over.
  ///
  /// Low-confidence fixes are dropped here, before anything is derived from
  /// them: a bad position is worse than a missing one, because the gap it
  /// leaves is bridged by the next accepted sample while the bad fix would be
  /// integrated into the distance total.
  static Map<String, List<PositionSample>> groupByTag(
    Iterable<PositionSample> samples, {
    AnalyticsThresholds thresholds = AnalyticsThresholds.defaults,
  }) {
    final byTag = <String, List<PositionSample>>{};
    for (final sample in samples) {
      if (sample.confidence < thresholds.minConfidence) continue;
      (byTag[sample.tagId] ??= []).add(sample);
    }
    for (final track in byTag.values) {
      track.sort((a, b) => a.timestampMicros.compareTo(b.timestampMicros));
    }
    return byTag;
  }

  /// Computes metrics from frames, the shape replay already holds.
  factory SessionMetrics.fromFrames(
    Iterable<PositionFrame> frames, {
    AnalyticsThresholds thresholds = AnalyticsThresholds.defaults,
  }) =>
      SessionMetrics.fromSamples(
        [for (final frame in frames) ...frame.samples],
        thresholds: thresholds,
      );

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

  /// Metrics for one uninterrupted, time-ordered stretch of a tag's track.
  ///
  /// Public so that a stretch can be chosen by something other than "all of
  /// it" — an on-court stint, or the part of one spent attacking — and
  /// measured on exactly the same arithmetic as the whole recording is.
  /// Combine the results with [PlayerTrackMetrics.merged].
  static PlayerTrackMetrics forTrack(
    String tagId,
    List<PositionSample> track, {
    AnalyticsThresholds thresholds = AnalyticsThresholds.defaults,
  }) {
    if (track.isEmpty) return PlayerTrackMetrics.empty(tagId);
    track.sort((a, b) => a.timestampMicros.compareTo(b.timestampMicros));

    final maxPlausibleSpeedMps = thresholds.maxPlausibleSpeedMps;
    final speedWindowMicros = thresholds.speedWindow.inMicroseconds;

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
    // least one speed window old. `window` only ever moves forward, so the
    // pass is linear rather than quadratic.
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
              speedWindowMicros) {
        window++;
      }

      final dtMicros =
          track[i].timestampMicros - track[window].timestampMicros;
      if (dtMicros < speedWindowMicros) continue;

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
