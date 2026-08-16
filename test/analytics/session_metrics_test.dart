import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/analytics_thresholds.dart';
import 'package:kinetag/src/analytics/session_metrics.dart';
import 'package:kinetag/src/domain/domain.dart';

const int kStartMicros = 1786000000000000;

/// A straight track along X at [speedMps], sampled at [hz].
List<PositionSample> straightTrack({
  String tagId = 'tag-1',
  double speedMps = 5.0,
  int hz = 20,
  double seconds = 4.0,
  double y = 10,
}) {
  final stepMicros = (1e6 / hz).round();
  final count = (seconds * hz).round() + 1;
  return [
    for (var i = 0; i < count; i++)
      PositionSample(
        timestampMicros: kStartMicros + i * stepMicros,
        tagId: tagId,
        x: speedMps * (i * stepMicros / 1e6),
        y: y,
      ),
  ];
}

void main() {
  group('distance', () {
    test('measures the path length of a straight run', () {
      // 5 m/s for 4 s = 20 m.
      final metrics = SessionMetrics.fromSamples(straightTrack());

      expect(metrics.forTag('tag-1')!.distanceMeters, closeTo(20.0, 1e-6));
    });

    test('follows a path rather than the straight line between its ends', () {
      // Out 10 m and back: 20 m covered, ending where it started.
      final out = straightTrack(speedMps: 5, seconds: 2);
      final back = [
        for (var i = 1; i <= 40; i++)
          PositionSample(
            timestampMicros: out.last.timestampMicros + i * 50000,
            tagId: 'tag-1',
            x: 10 - 5 * (i * 50000 / 1e6),
            y: 10,
          ),
      ];

      final metrics = SessionMetrics.fromSamples([...out, ...back]);

      expect(metrics.forTag('tag-1')!.distanceMeters, closeTo(20.0, 1e-6));
    });

    test('a stationary tag covers no distance', () {
      final still = [
        for (var i = 0; i < 100; i++)
          PositionSample(
            timestampMicros: kStartMicros + i * 50000,
            tagId: 'tag-1',
            x: 20,
            y: 10,
          ),
      ];

      final metrics = SessionMetrics.fromSamples(still);
      expect(metrics.forTag('tag-1')!.distanceMeters, 0);
      expect(metrics.forTag('tag-1')!.maxSpeedMps, 0);
    });

    test('discards a physically impossible jump', () {
      // A 30 m teleport and back would otherwise add 60 m of phantom running.
      final track = straightTrack(seconds: 2);
      final glitch = PositionSample(
        timestampMicros: track[20].timestampMicros + 1,
        tagId: 'tag-1',
        x: track[20].x + 30,
        y: 10,
      );
      final withGlitch = [...track.take(21), glitch, ...track.skip(21)];

      final clean = SessionMetrics.fromSamples(track).forTag('tag-1')!;
      final dirty = SessionMetrics.fromSamples(withGlitch).forTag('tag-1')!;

      // One bad step is dropped, and the next one bridges the gap from the
      // last good position, so the real movement across the glitch survives.
      expect(dirty.discardedSteps, 1);
      expect(dirty.distanceMeters, closeTo(clean.distanceMeters, 1e-6));
      expect(dirty.maxSpeedMps, lessThan(AnalyticsThresholds.defaults.maxPlausibleSpeedMps));
    });

    test('ignores duplicate timestamps instead of dividing by zero', () {
      final duplicated = [
        ...straightTrack(seconds: 1),
        PositionSample(
          timestampMicros: kStartMicros,
          tagId: 'tag-1',
          x: 0,
          y: 10,
        ),
      ];

      final metrics = SessionMetrics.fromSamples(duplicated);
      expect(metrics.forTag('tag-1')!.distanceMeters, closeTo(5.0, 1e-6));
    });
  });

  group('speed', () {
    test('reports the max speed of a constant-speed run', () {
      final metrics =
          SessionMetrics.fromSamples(straightTrack(speedMps: 6.5)).forTag('tag-1')!;

      expect(metrics.maxSpeedMps, closeTo(6.5, 1e-6));
    });

    test('finds the fastest stretch of a varying run', () {
      // 2 m/s for 2 s, then 8 m/s for 2 s.
      final samples = <PositionSample>[];
      var x = 0.0;
      for (var i = 0; i <= 80; i++) {
        final speed = i < 40 ? 2.0 : 8.0;
        if (i > 0) x += speed * 0.05;
        samples.add(PositionSample(
          timestampMicros: kStartMicros + i * 50000,
          tagId: 'tag-1',
          x: x,
          y: 10,
        ));
      }

      final metrics = SessionMetrics.fromSamples(samples).forTag('tag-1')!;

      expect(metrics.maxSpeedMps, closeTo(8.0, 0.2));
      expect(metrics.averageSpeedMps, closeTo(5.0, 0.1));
    });

    test('a window keeps position noise out of the maximum', () {
      // A stationary tag jittering +/-5 cm every sample: sample-to-sample
      // speed would read 2 m/s, the windowed speed reads almost nothing.
      final jittery = [
        for (var i = 0; i < 200; i++)
          PositionSample(
            timestampMicros: kStartMicros + i * 50000,
            tagId: 'tag-1',
            x: 20 + (i.isEven ? 0.05 : -0.05),
            y: 10,
          ),
      ];

      final metrics = SessionMetrics.fromSamples(jittery).forTag('tag-1')!;

      expect(metrics.maxSpeedMps, lessThan(0.6));
    });

    test('average speed counts standing still', () {
      // 5 m/s for 2 s, then stationary for 2 s: 10 m over 4 s.
      final moving = straightTrack(speedMps: 5, seconds: 2);
      final resting = [
        for (var i = 1; i <= 40; i++)
          PositionSample(
            timestampMicros: moving.last.timestampMicros + i * 50000,
            tagId: 'tag-1',
            x: moving.last.x,
            y: 10,
          ),
      ];

      final metrics =
          SessionMetrics.fromSamples([...moving, ...resting]).forTag('tag-1')!;

      expect(metrics.distanceMeters, closeTo(10.0, 1e-6));
      expect(metrics.averageSpeedMps, closeTo(2.5, 0.05));
    });

    test('instantaneous speed can be read at the replay playhead', () {
      final samples = <PositionSample>[];
      var x = 0.0;
      for (var i = 0; i <= 80; i++) {
        final speed = i < 40 ? 1.0 : 7.0;
        if (i > 0) x += speed * 0.05;
        samples.add(PositionSample(
          timestampMicros: kStartMicros + i * 50000,
          tagId: 'tag-1',
          x: x,
          y: 10,
        ));
      }
      final metrics = SessionMetrics.fromSamples(samples).forTag('tag-1')!;

      expect(metrics.speedAt(kStartMicros - 1), 0, reason: 'before the start');
      expect(metrics.speedAt(kStartMicros + 30 * 50000), closeTo(1.0, 0.05));
      expect(metrics.speedAt(kStartMicros + 70 * 50000), closeTo(7.0, 0.05));
      expect(metrics.speedAt(kStartMicros + 999 * 50000), closeTo(7.0, 0.05),
          reason: 'past the end, the last known speed holds');
    });
  });

  group('sessions', () {
    test('keeps players apart and ranks them by distance', () {
      final metrics = SessionMetrics.fromSamples([
        ...straightTrack(tagId: 'slow', speedMps: 2),
        ...straightTrack(tagId: 'fast', speedMps: 6),
      ]);

      expect(metrics.byTagId.keys, containsAll(['slow', 'fast']));
      expect(metrics.byDistance.first.tagId, 'fast');
      expect(metrics.totalDistanceMeters, closeTo(8.0 + 24.0, 1e-6));
    });

    test('is computed identically from frames or from samples', () {
      final samples = [
        ...straightTrack(tagId: 'a'),
        ...straightTrack(tagId: 'b', speedMps: 3),
      ];
      final frames = PositionFrame.groupByTimestamp(samples);

      final fromSamples = SessionMetrics.fromSamples(samples);
      final fromFrames = SessionMetrics.fromFrames(frames);

      expect(fromFrames.totalDistanceMeters,
          closeTo(fromSamples.totalDistanceMeters, 1e-9));
    });

    test('handles an empty recording and a single sample', () {
      expect(SessionMetrics.fromSamples(const []).isEmpty, isTrue);

      final single = SessionMetrics.fromSamples([
        PositionSample(
          timestampMicros: kStartMicros,
          tagId: 'tag-1',
          x: 1,
          y: 1,
        ),
      ]).forTag('tag-1')!;

      expect(single.sampleCount, 1);
      expect(single.distanceMeters, 0);
      expect(single.averageSpeedMps, 0);
      expect(single.trackedDuration, Duration.zero);
    });

    test('reports the tracked span of each player', () {
      final metrics = SessionMetrics.fromSamples(straightTrack(seconds: 4))
          .forTag('tag-1')!;

      expect(metrics.trackedDuration, const Duration(seconds: 4));
      expect(metrics.sampleCount, 81);
    });

    test('samples arriving out of order are sorted before measuring', () {
      // Storage returns rows in time order, but nothing in the type system
      // guarantees a caller does.
      final ordered = straightTrack(seconds: 2);
      final shuffled = [...ordered.reversed];

      expect(
        SessionMetrics.fromSamples(shuffled).forTag('tag-1')!.distanceMeters,
        closeTo(
          SessionMetrics.fromSamples(ordered).forTag('tag-1')!.distanceMeters,
          1e-9,
        ),
      );
    });
  });
}
