import 'package:meta/meta.dart';

import '../domain/domain.dart';
import 'analytics_thresholds.dart';
import 'court_presence.dart';
import 'timeline_runs.dart';

/// Which way a team was playing.
enum PlayPhase {
  attacking('Attacking'),
  defending('Defending'),

  /// Neither could be established: no goalkeeper was tracked, the signal sat
  /// on the fence, or the player has no side and so has no end to attack.
  unclear('Unclear');

  const PlayPhase(this.label);

  final String label;
}

/// Which side was attacking, over the course of a recording.
///
/// ## The measurement
///
/// A goalkeeper's distance from their own goal line is the cheapest honest
/// indicator of where play is. When their team attacks, a keeper leaves the
/// line and follows the play up the court; when it defends, they are back on
/// it. No ball is tracked, and no other player has to be identified — the
/// keeper is the one position whose *longitudinal* place on the court is
/// determined by possession rather than by tactics.
///
/// Three things turn that observation into a usable signal:
///
/// 1. **Self-calibration.** Each keeper's advance is centred on the midpoint of
///    its own 10th and 90th percentiles, so what is measured is how far this
///    keeper moved *for them*. A keeper who habitually stands two metres off
///    their line no longer reads as permanently attacking, and — because a
///    midpoint of percentiles is not a mean — a team that attacked for two
///    thirds of the match does not drag its own centre into its attacking half.
/// 2. **Differencing the two ends.** Both keepers see the same possession from
///    opposite sides, so subtracting one from the other doubles the signal
///    while their unrelated drift partly cancels. With only one keeper tracked
///    the remaining term is used alone, which is why the signal is the *mean*
///    of the available terms rather than their difference: the scale, and so
///    the meaning of [PlayThresholds.possessionMarginMeters], stays the same
///    either way.
/// 3. **Smoothing, then a margin with memory.** The mean is averaged over
///    [PlayThresholds.possessionWindow] and then thresholded by a trigger that
///    holds its last decision until the signal crosses the *opposite* margin.
///    Between the two margins nothing changes hands, which is the point: in
///    handball possession is never jointly held, so a phase ends when the other
///    one begins.
///
/// ## What it cannot do
///
/// It is an inference, not an event log. A fast break is over before a keeper
/// has finished reacting to it, so the timeline lags the truth by a second or
/// so and will miss the shortest possessions entirely. It needs a goalkeeper
/// on the roster: with none, [isAvailable] is false and every phase is
/// [PlayPhase.unclear] rather than guessed at. And because the centring is
/// computed across the whole recording, this can only be done afterwards —
/// it is analysis, not something the live view could show.
@immutable
class PossessionTimeline {
  /// Attacking side over time; a null value is a stretch that could not be
  /// determined. Half-open and contiguous, so the durations partition the
  /// measured span.
  final List<TimedRun<TeamSide?>> runs;

  /// The sides a goalkeeper was actually tracked for.
  final Set<TeamSide> keeperSides;

  final PlayThresholds thresholds;

  const PossessionTimeline({
    required this.runs,
    required this.keeperSides,
    this.thresholds = PlayThresholds.defaults,
  });

  /// The timeline for a recording nothing can be inferred from.
  static const PossessionTimeline unavailable =
      PossessionTimeline(runs: [], keeperSides: {});

  /// How often the keeper signal is evaluated.
  ///
  /// A quarter of a second is far finer than the phenomenon — possessions run
  /// to tens of seconds — and coarse enough that a long recording resolves to
  /// a few thousand points rather than to every sample of every tag. Sampling
  /// onto a common grid is also what lets two keepers reporting at different
  /// instants be compared at all.
  static const Duration gridStep = Duration(milliseconds: 250);

  /// How stale a keeper's last position may be before the grid point it would
  /// have filled is left empty instead.
  ///
  /// Without it, a keeper whose tag drops out for a minute would hold the last
  /// phase for that minute, and a whole possession would be attributed on the
  /// strength of a position that is no longer being measured.
  static const Duration maxKeeperGap = Duration(seconds: 1);

  /// Infers the timeline from the goalkeepers in [session]'s roster snapshot.
  ///
  /// [tracks] are the per-tag, time-ordered, confidence-filtered samples from
  /// `SessionMetrics.groupByTag`; [presence] is used to ignore a keeper who is
  /// sitting on the bench, whose distance from the goal line means nothing.
  factory PossessionTimeline.fromKeepers({
    required Map<String, List<PositionSample>> tracks,
    required Session session,
    required SessionPresence presence,
    PlayThresholds thresholds = PlayThresholds.defaults,
  }) {
    final keepers = <TeamSide, List<String>>{};
    for (final tagId in tracks.keys) {
      final player = session.playerForTag(tagId);
      final side = player?.side;
      if (player?.role != PlayerRole.goalkeeper || side == null) continue;
      if (tracks[tagId]!.isEmpty) continue;
      (keepers[side] ??= []).add(tagId);
    }
    if (keepers.isEmpty) return unavailable;

    var firstMicros = 0;
    var lastMicros = 0;
    var seen = false;
    for (final tags in keepers.values) {
      for (final tagId in tags) {
        final track = tracks[tagId]!;
        if (!seen) {
          firstMicros = track.first.timestampMicros;
          lastMicros = track.last.timestampMicros;
          seen = true;
          continue;
        }
        if (track.first.timestampMicros < firstMicros) {
          firstMicros = track.first.timestampMicros;
        }
        if (track.last.timestampMicros > lastMicros) {
          lastMicros = track.last.timestampMicros;
        }
      }
    }

    final stepMicros = gridStep.inMicroseconds;
    final points = (lastMicros - firstMicros) ~/ stepMicros + 1;
    if (points < 2) return unavailable;

    // One centred advance series per end, then the mean of whichever ends were
    // measured — see the class comment for why a mean and not a difference.
    final signal = List<double?>.filled(points, null);
    final terms = List<int>.filled(points, 0);

    for (final entry in keepers.entries) {
      final side = entry.key;
      final advance = _advanceSeries(
        side: side,
        tagIds: entry.value,
        tracks: tracks,
        presence: presence,
        court: session.court,
        firstMicros: firstMicros,
        stepMicros: stepMicros,
        points: points,
      );
      _centre(advance);

      final sign = side == TeamSide.home ? 1.0 : -1.0;
      for (var i = 0; i < points; i++) {
        final value = advance[i];
        if (value == null) continue;
        signal[i] = (signal[i] ?? 0) + sign * value;
        terms[i]++;
      }
    }
    for (var i = 0; i < points; i++) {
      if (terms[i] > 0) signal[i] = signal[i]! / terms[i];
    }

    final smoothed = _boxSmooth(
      signal,
      halfWidth: thresholds.possessionWindow.inMicroseconds ~/ (2 * stepMicros),
    );

    // The trigger with memory: cross a margin to take possession, and hold it
    // until the other side crosses theirs.
    final margin = thresholds.possessionMarginMeters;
    final states = List<TeamSide?>.filled(points, null);
    TeamSide? state;
    for (var i = 0; i < points; i++) {
      final value = smoothed[i];
      if (value == null) {
        state = null;
      } else if (value > margin) {
        state = TeamSide.home;
      } else if (value < -margin) {
        state = TeamSide.away;
      }
      states[i] = state;
    }

    return PossessionTimeline(
      runs: buildRuns<TeamSide?>(
        length: points,
        valueAt: (i) => states[i],
        timeAt: (i) => firstMicros + i * stepMicros,
        endMicros: lastMicros,
        minDuration: thresholds.minPossession,
      ),
      keeperSides: keepers.keys.toSet(),
      thresholds: thresholds,
    );
  }

  /// How far up the court [side]'s keeper stood at each grid point, in metres
  /// from their own goal line; null where none was measured.
  ///
  /// With two keepers of one side on court — a second one playing out, which
  /// the rules allow — the smaller advance wins: the one nearer the goal is the
  /// one actually keeping it.
  static List<double?> _advanceSeries({
    required TeamSide side,
    required List<String> tagIds,
    required Map<String, List<PositionSample>> tracks,
    required SessionPresence presence,
    required Court court,
    required int firstMicros,
    required int stepMicros,
    required int points,
  }) {
    final series = List<double?>.filled(points, null);
    final staleMicros = maxKeeperGap.inMicroseconds;

    for (final tagId in tagIds) {
      final track = tracks[tagId]!;
      final stints = presence.forTag(tagId);

      // Both the grid and the track ascend, so one cursor walks the track once
      // rather than a search per grid point.
      var cursor = 0;
      for (var i = 0; i < points; i++) {
        final at = firstMicros + i * stepMicros;
        while (cursor + 1 < track.length &&
            track[cursor + 1].timestampMicros <= at) {
          cursor++;
        }

        final sample = track[cursor];
        if (sample.timestampMicros > at) continue;
        if (at - sample.timestampMicros > staleMicros) continue;
        if (!stints.isOnCourtAt(sample.timestampMicros)) continue;

        final advance =
            side == TeamSide.home ? sample.x : court.widthMeters - sample.x;
        final current = series[i];
        if (current == null || advance < current) series[i] = advance;
      }
    }

    return series;
  }

  /// Shifts [series] so that zero is this keeper's own neutral position.
  ///
  /// The centre is the midpoint of the 10th and 90th percentiles rather than
  /// the median or the mean, both of which drift toward whichever phase the
  /// team spent longer in. The midpoint of two symmetric tails does not.
  static void _centre(List<double?> series) {
    final values = [for (final value in series) ?value]..sort();
    if (values.isEmpty) return;

    final low = values[((values.length - 1) * 0.1).round()];
    final high = values[((values.length - 1) * 0.9).round()];
    final centre = (low + high) / 2;

    for (var i = 0; i < series.length; i++) {
      final value = series[i];
      if (value != null) series[i] = value - centre;
    }
  }

  /// A centred moving average that steps over the gaps rather than filling
  /// them: a window with nothing measured in it stays empty.
  static List<double?> _boxSmooth(List<double?> series, {required int halfWidth}) {
    if (halfWidth <= 0) return series;

    // Prefix sums make the window cost independent of its width, which matters
    // because the window is seconds wide and the grid is a quarter-second.
    final sums = List<double>.filled(series.length + 1, 0);
    final counts = List<int>.filled(series.length + 1, 0);
    for (var i = 0; i < series.length; i++) {
      final value = series[i];
      sums[i + 1] = sums[i] + (value ?? 0);
      counts[i + 1] = counts[i] + (value == null ? 0 : 1);
    }

    return [
      for (var i = 0; i < series.length; i++)
        () {
          final from = (i - halfWidth).clamp(0, series.length);
          final to = (i + halfWidth + 1).clamp(0, series.length);
          final count = counts[to] - counts[from];
          return count == 0 ? null : (sums[to] - sums[from]) / count;
        }(),
    ];
  }

  /// Whether any phase at all could be established.
  bool get isAvailable => runs.any((run) => run.value != null);

  Duration get measuredDuration => runs.isEmpty
      ? Duration.zero
      : Duration(microseconds: runs.last.endMicros - runs.first.startMicros);

  /// The side attacking at [micros], or null where it is undetermined.
  TeamSide? attackingAt(int micros) {
    var low = 0;
    var high = runs.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final run = runs[mid];
      if (micros < run.startMicros) {
        high = mid - 1;
      } else if (micros >= run.endMicros) {
        low = mid + 1;
      } else {
        return run.value;
      }
    }
    return null;
  }

  /// The phase [side] was in at [micros].
  PlayPhase phaseAt(int micros, TeamSide? side) =>
      _phaseFor(attackingAt(micros), side);

  /// The whole timeline seen from [side]: the same stretches, relabelled as
  /// what that team was doing during them.
  ///
  /// A null [side] — a tag whose wearer has no team — yields
  /// [PlayPhase.unclear] throughout. Attacking and defending are statements
  /// about which end a player is heading for, and without a side there is no
  /// end to name.
  List<TimedRun<PlayPhase>> phasesFor(TeamSide? side) => [
        for (final run in runs)
          TimedRun(
            startMicros: run.startMicros,
            endMicros: run.endMicros,
            value: _phaseFor(run.value, side),
          ),
      ];

  /// How long [side] spent in [phase] over the whole recording, irrespective
  /// of who was on court.
  Duration teamTimeIn(TeamSide side, PlayPhase phase) => Duration(
        microseconds: runs.fold(
          0,
          (sum, run) =>
              _phaseFor(run.value, side) == phase ? sum + run.durationMicros : sum,
        ),
      );

  static PlayPhase _phaseFor(TeamSide? attacking, TeamSide? side) {
    if (attacking == null || side == null) return PlayPhase.unclear;
    return attacking == side ? PlayPhase.attacking : PlayPhase.defending;
  }

  @override
  String toString() => 'PossessionTimeline(${runs.length} phases, '
      'keepers: ${keeperSides.map((s) => s.displayName).join('/')})';
}
