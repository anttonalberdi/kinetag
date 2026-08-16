import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/play_metrics.dart';
import 'package:kinetag/src/analytics/session_metrics.dart';
import 'package:kinetag/src/domain/domain.dart';

const int kStartMicros = 1786000000000000;
const int kStepMicros = 50000; // 20 Hz

final Court court = Court.handball();

/// A track sampled at 20 Hz whose position at second `t` is given by [at].
List<PositionSample> track(
  String tagId,
  double seconds,
  (double, double) Function(double t) at,
) {
  final count = (seconds * 1e6 / kStepMicros).round() + 1;
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = i * kStepMicros / 1e6;
        final (x, y) = at(t);
        return PositionSample(
          timestampMicros: kStartMicros + i * kStepMicros,
          tagId: tagId,
          x: x,
          y: y,
        );
      }(),
  ];
}

Session sessionOf(List<String> tagIds, {Duration? duration}) => Session(
      id: 'session-1',
      name: 'Test session',
      createdAt: DateTime.fromMicrosecondsSinceEpoch(kStartMicros, isUtc: true),
      court: court,
      tags: [for (final id in tagIds) Tag(id: id, hardwareId: id, name: id)],
      players: [
        for (final id in tagIds)
          Player(id: 'player-$id', name: 'Player $id', side: TeamSide.home),
      ],
      tagAssignments: [
        for (final id in tagIds)
          TagAssignment(id: 'a-$id', playerId: 'player-$id', tagId: id),
      ],
      status: SessionStatus.completed,
      startedAt: DateTime.fromMicrosecondsSinceEpoch(kStartMicros, isUtc: true),
      stoppedAt: duration == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              kStartMicros + duration.inMicroseconds,
              isUtc: true,
            ),
    );

SessionPlayMetrics metricsFor(
  List<PositionSample> samples, {
  Session? session,
}) {
  final resolved = session ??
      sessionOf(samples.map((s) => s.tagId).toSet().toList());
  return SessionPlayMetrics.from(
    metrics: SessionMetrics.fromSamples(samples),
    samples: samples,
    session: resolved,
  );
}

void main() {
  group('bench time', () {
    // Runs up and down the court at 4 m/s for the first minute, sits on the
    // bench for the second, comes back for the third.
    List<PositionSample> rotatingPlayer() => track('tag-1', 180, (t) {
          if (t >= 60 && t < 120) return (20.0, -0.5);
          final leg = t % 10;
          return (5 + 4 * (leg < 5 ? leg : 10 - leg), 10.0);
        });

    test('playing time and bench time are reported separately', () {
      final player = metricsFor(rotatingPlayer()).forTag('tag-1')!;

      expect(player.onCourtDuration, const Duration(seconds: 120));
      expect(player.benchDuration, const Duration(seconds: 60));
      expect(player.stintCount, 2);
    });

    test('distance excludes what happened off the court', () {
      final player = metricsFor(rotatingPlayer()).forTag('tag-1')!;

      final whole = player.forSplit(PlaySplit.all);
      final playing = player.forSplit(PlaySplit.onCourt);

      expect(playing.distanceMeters, lessThan(whole.distanceMeters));
      // Two minutes of running at 4 m/s, and none of the walk to the seat.
      expect(playing.distanceMeters, closeTo(480, 20));
    });

    test('average speed is not diluted by sitting down', () {
      final player = metricsFor(rotatingPlayer()).forTag('tag-1')!;

      final whole = player.forSplit(PlaySplit.all);
      final playing = player.forSplit(PlaySplit.onCourt);

      expect(playing.averageSpeedMps, closeTo(4.0, 0.2));
      expect(whole.averageSpeedMps, lessThan(playing.averageSpeedMps),
          reason: 'the bench minute drags the whole-recording figure down');
    });

    test('the splits add back up to the whole recording', () {
      final player = metricsFor(rotatingPlayer()).forTag('tag-1')!;

      final whole = player.forSplit(PlaySplit.all).trackedDuration;
      final parts = player.forSplit(PlaySplit.onCourt).trackedDuration +
          player.forSplit(PlaySplit.bench).trackedDuration;

      // One sample of slack per boundary: the instant of a switch is only
      // known to the rate the tag reports at.
      expect((parts - whole).inMilliseconds.abs(), lessThan(200));
    });

    test('a player who never left the court has no bench time', () {
      final player = metricsFor(
        track('tag-1', 120, (t) => (20 + 5 * (t % 2), 10)),
      ).forTag('tag-1')!;

      expect(player.benchDuration, Duration.zero);
      expect(
        player.forSplit(PlaySplit.onCourt).distanceMeters,
        closeTo(player.forSplit(PlaySplit.all).distanceMeters, 1e-6),
      );
    });
  });

  group('relative time', () {
    test('playing time is reported against the session it belongs to', () {
      final samples = track('tag-1', 180, (t) =>
          t >= 60 && t < 120 ? (20.0, -0.5) : (20.0, 10.0));
      final metrics = metricsFor(
        samples,
        session: sessionOf(['tag-1'], duration: const Duration(minutes: 4)),
      );

      expect(metrics.sessionDuration, const Duration(minutes: 4));
      expect(
        metrics.forTag('tag-1')!.onCourtShareOf(metrics.sessionDuration),
        closeTo(120 / 240, 1e-6),
      );
    });

    test('a session that never recorded its span falls back to the tracks', () {
      final metrics = metricsFor(track('tag-1', 90, (t) => (20, 10)));

      expect(metrics.sessionDuration, const Duration(seconds: 90));
    });
  });

  group('phases', () {
    test('without a goalkeeper everything on court is unclear', () {
      final player = metricsFor(
        track('tag-1', 120, (t) => (20 + 5 * (t % 2), 10)),
      ).forTag('tag-1')!;

      expect(player.hasPhaseSplit, isFalse);
      expect(player.forSplit(PlaySplit.attacking).trackedDuration,
          Duration.zero);
      expect(player.forSplit(PlaySplit.unclear).trackedDuration,
          player.forSplit(PlaySplit.onCourt).trackedDuration);
    });
  });

  group('sessions', () {
    test('an empty recording measures nothing without failing', () {
      final metrics = metricsFor(const []);

      expect(metrics.isEmpty, isTrue);
      expect(metrics.hasPhases, isFalse);
      expect(metrics.totalPlayingTime, Duration.zero);
      expect(metrics.tracksFor(PlaySplit.onCourt), isEmpty);
    });

    test('playing and bench time are totalled across the squad', () {
      final metrics = metricsFor([
        ...track('tag-1', 120, (t) => (20, 10)),
        ...track('tag-2', 120, (t) => t < 60 ? (20, -0.5) : (20, 10)),
      ]);

      expect(metrics.totalPlayingTime, const Duration(seconds: 180));
      expect(metrics.totalBenchTime, const Duration(seconds: 60));
      expect(metrics.hasBenchTime, isTrue);
    });
  });
}
