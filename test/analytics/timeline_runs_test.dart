import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/timeline_runs.dart';

/// Builds runs from a list of states, one per second.
List<TimedRun<String>> runsOf(
  List<String> states, {
  Duration minDuration = const Duration(seconds: 3),
}) =>
    buildRuns<String>(
      length: states.length,
      valueAt: (i) => states[i],
      timeAt: (i) => i * 1000000,
      endMicros: (states.length - 1) * 1000000,
      minDuration: minDuration,
    );

void main() {
  test('a constant classification is one run spanning everything', () {
    final runs = runsOf(List.filled(10, 'a'));

    expect(runs, hasLength(1));
    expect(runs.single.value, 'a');
    expect(runs.single.duration, const Duration(seconds: 9));
  });

  test('runs partition the span with no gap and no overlap', () {
    final runs = runsOf([
      ...List.filled(5, 'a'),
      ...List.filled(5, 'b'),
      ...List.filled(5, 'a'),
    ]);

    expect(runs.map((r) => r.value), ['a', 'b', 'a']);
    for (var i = 1; i < runs.length; i++) {
      expect(runs[i].startMicros, runs[i - 1].endMicros,
          reason: 'each run begins exactly where the last one ended');
    }
    expect(
      runs.fold(Duration.zero, (sum, r) => sum + r.duration),
      const Duration(seconds: 14),
      reason: 'the parts add up to the whole',
    );
  });

  test('a flicker too short to believe is absorbed by what preceded it', () {
    // One second of 'b' in the middle of ten of 'a' is noise, not an event.
    final runs = runsOf([...List.filled(5, 'a'), 'b', ...List.filled(5, 'a')]);

    expect(runs, hasLength(1));
    expect(runs.single.value, 'a');
  });

  test('a short opening run is absorbed by the one that follows it', () {
    final runs = runsOf(['b', ...List.filled(9, 'a')]);

    expect(runs, hasLength(1));
    expect(runs.single.value, 'a');
    expect(runs.single.startMicros, 0,
        reason: 'absorbing must not lose the time at the start');
  });

  test('a run long enough to believe survives', () {
    final runs = runsOf([
      ...List.filled(5, 'a'),
      ...List.filled(4, 'b'),
      ...List.filled(5, 'a'),
    ]);

    expect(runs.map((r) => r.value), ['a', 'b', 'a']);
  });

  test('the closing sample carries no time and cannot open a run', () {
    // The last classification closes the span rather than starting a new
    // stretch of it, so a lone one at the end is not an event.
    final runs = runsOf([...List.filled(9, 'a'), 'b']);

    expect(runs, hasLength(1));
    expect(runs.single.value, 'a');
  });

  test('a span shorter than the minimum is one state, not none', () {
    final runs = runsOf(
      ['a', 'a', 'a', 'b', 'b'],
      minDuration: const Duration(minutes: 1),
    );

    expect(runs, hasLength(1));
    expect(runs.single.value, 'a', reason: 'the state with evidence behind it');
  });

  test('an empty classification produces no runs', () {
    expect(runsOf(const []), isEmpty);
  });
}
