import 'package:meta/meta.dart';

/// A stretch of time over which one classification held.
///
/// The half-open convention — [startMicros] inclusive, [endMicros] exclusive —
/// is what makes a list of these a partition rather than a set of overlapping
/// claims: every instant of a recording belongs to exactly one run, so the
/// durations add up to the whole and no moment is counted twice.
@immutable
class TimedRun<T> {
  final int startMicros;
  final int endMicros;
  final T value;

  const TimedRun({
    required this.startMicros,
    required this.endMicros,
    required this.value,
  });

  Duration get duration => Duration(microseconds: endMicros - startMicros);

  int get durationMicros => endMicros - startMicros;

  bool containsTime(int micros) => micros >= startMicros && micros < endMicros;

  TimedRun<T> copyWith({int? startMicros, int? endMicros}) => TimedRun(
        startMicros: startMicros ?? this.startMicros,
        endMicros: endMicros ?? this.endMicros,
        value: value,
      );

  @override
  String toString() => 'TimedRun($value, '
      '${(durationMicros / 1e6).toStringAsFixed(1)} s)';
}

/// Turns a per-sample classification into the stretches of time it held for,
/// discarding stretches too short to be believed.
///
/// ## Why the short ones go
///
/// Both things this app classifies over time — whether a player is on court,
/// and which way their team is playing — are physical states that persist.
/// A player is substituted for a shift, not for half a second; a team attacks
/// for a possession. So a classification that flips and flips back within a
/// couple of seconds is describing measurement noise or a moment of ambiguity,
/// not an event, and reporting it as an event would fill a coach's substitution
/// count with fictional substitutions.
///
/// Runs below [minDuration] are therefore absorbed, shortest first — the
/// least-supported classification is the one to give up, and taking them in
/// that order stops a run being absorbed into a neighbour that is itself about
/// to disappear. A run is absorbed into the one *before* it, which is a
/// deliberate bias: the state already established has evidence behind it, and a
/// brief contradiction is more likely to be wrong than the minutes that
/// preceded it. The first run has nothing before it and is absorbed into the
/// run that follows instead. Absorbing can leave two neighbours with the same
/// value, so the runs are coalesced afterwards.
///
/// [timeAt] gives the instant classification `i` was made; [endMicros] closes
/// the last run, and must not precede the final instant.
List<TimedRun<T>> buildRuns<T>({
  required int length,
  required T Function(int index) valueAt,
  required int Function(int index) timeAt,
  required int endMicros,
  required Duration minDuration,
}) {
  if (length <= 0) return const [];

  final runs = <TimedRun<T>>[];
  var runStart = 0;
  for (var i = 1; i <= length; i++) {
    if (i < length && valueAt(i) == valueAt(runStart)) continue;
    runs.add(
      TimedRun(
        startMicros: timeAt(runStart),
        endMicros: i < length ? timeAt(i) : endMicros,
        value: valueAt(runStart),
      ),
    );
    runStart = i;
  }

  return _coalesce(_absorbShortRuns(runs, minDuration.inMicroseconds));
}

/// Repeatedly folds the shortest too-short run into a neighbour until none is
/// left, or until only one run remains — a recording shorter than the minimum
/// is a single state, not no state at all.
List<TimedRun<T>> _absorbShortRuns<T>(List<TimedRun<T>> runs, int minMicros) {
  final result = [...runs];

  while (result.length > 1) {
    var shortest = -1;
    for (var i = 0; i < result.length; i++) {
      if (result[i].durationMicros >= minMicros) continue;
      if (shortest < 0 ||
          result[i].durationMicros < result[shortest].durationMicros) {
        shortest = i;
      }
    }
    if (shortest < 0) break;

    if (shortest > 0) {
      result[shortest - 1] =
          result[shortest - 1].copyWith(endMicros: result[shortest].endMicros);
    } else {
      result[1] = result[1].copyWith(startMicros: result[0].startMicros);
    }
    result.removeAt(shortest);
  }

  return result;
}

List<TimedRun<T>> _coalesce<T>(List<TimedRun<T>> runs) {
  final result = <TimedRun<T>>[];
  for (final run in runs) {
    if (result.isNotEmpty && result.last.value == run.value) {
      result[result.length - 1] =
          result.last.copyWith(endMicros: run.endMicros);
      continue;
    }
    result.add(run);
  }
  return result;
}
