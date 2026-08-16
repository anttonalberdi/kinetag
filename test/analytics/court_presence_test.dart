import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/court_presence.dart';
import 'package:kinetag/src/domain/domain.dart';

const int kStartMicros = 1786000000000000;
const int kStepMicros = 50000; // 20 Hz

final Court court = Court.handball();

/// A track sampled at 20 Hz whose position at second `t` is given by [at].
List<PositionSample> track(
  double seconds,
  (double, double) Function(double t) at, {
  String tagId = 'tag-1',
}) {
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

void main() {
  group('segmentation', () {
    test('a player who never leaves the court has one stint', () {
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(120, (t) => (20 + 5 * (t % 2), 10)),
        court: court,
      );

      expect(presence.stintCount, 1);
      expect(presence.benchDuration, Duration.zero);
      expect(presence.onCourtDuration, const Duration(seconds: 120));
      expect(presence.onCourtShare, 1.0);
    });

    test('a substitution is found as a bench spell between two stints', () {
      // On for 60 s, on the bench half a metre outside the sideline for 60 s,
      // then back on for 60 s.
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(180, (t) => t >= 60 && t < 120 ? (20, -0.5) : (20, 10)),
        court: court,
      );

      expect(presence.stints.map((s) => s.value), [
        CourtPresence.onCourt,
        CourtPresence.bench,
        CourtPresence.onCourt,
      ]);
      expect(presence.stintCount, 2);
      expect(presence.benchDuration, const Duration(seconds: 60));
      expect(presence.onCourtDuration, const Duration(seconds: 120));
      expect(presence.onCourtShare, closeTo(2 / 3, 1e-6));
    });

    test('on-court and bench time add up to the tracked span', () {
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(180, (t) => t >= 60 && t < 120 ? (20, -0.5) : (20, 10)),
        court: court,
      );

      expect(
        presence.onCourtDuration + presence.benchDuration,
        presence.trackedDuration,
      );
    });

    test('a throw-in from behind the line is not a substitution', () {
      // Four seconds outside the sideline: legal, common, and far too short to
      // be a substitution.
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(120, (t) => t >= 60 && t < 64 ? (20, -0.6) : (20, 1.0)),
        court: court,
      );

      expect(presence.stintCount, 1);
      expect(presence.benchDuration, Duration.zero);
    });

    test('a wing on the sideline does not flicker on and off', () {
      // Standing on the line itself, jittering 15 cm either side of it — well
      // inside what real positioning error does.
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(120, (t) => (20, t.floor().isEven ? 0.15 : -0.15)),
        court: court,
      );

      expect(presence.stintCount, 1);
      expect(presence.benchDuration, Duration.zero,
          reason: 'the hysteresis band covers the jitter');
    });

    test('a player who starts on the bench starts benched', () {
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(120, (t) => t < 60 ? (20, -0.5) : (20, 10)),
        court: court,
      );

      expect(presence.stints.first.value, CourtPresence.bench);
      expect(presence.stintCount, 1);
      expect(presence.benchDuration, const Duration(seconds: 60));
    });

    test('a player who never comes on is never on court', () {
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(120, (t) => (20 + 0.9 * (t % 2), -0.5)),
        court: court,
      );

      expect(presence.everOnCourt, isFalse);
      expect(presence.onCourtDuration, Duration.zero);
      expect(presence.onCourtShare, 0);
    });
  });

  group('queries', () {
    test('the state can be read at an instant', () {
      final presence = PlayerPresence.fromTrack(
        'tag-1',
        track(180, (t) => t >= 60 && t < 120 ? (20, -0.5) : (20, 10)),
        court: court,
      );

      expect(presence.isOnCourtAt(kStartMicros + 30000000), isTrue);
      expect(presence.isOnCourtAt(kStartMicros + 90000000), isFalse);
      expect(presence.isOnCourtAt(kStartMicros + 150000000), isTrue);
      expect(presence.presenceAt(kStartMicros - 1), isNull,
          reason: 'nothing was measured before the recording');
      expect(presence.presenceAt(kStartMicros + 180000000),
          CourtPresence.onCourt,
          reason: 'the closing instant belongs to the last stint');
    });

    test('an empty track has no presence at all', () {
      final presence =
          PlayerPresence.fromTrack('tag-1', const [], court: court);

      expect(presence.stints, isEmpty);
      expect(presence.trackedDuration, Duration.zero);
      expect(presence.everOnCourt, isFalse);
      expect(presence.presenceAt(kStartMicros), isNull);
    });
  });

  group('sessions', () {
    test('keeps players apart and reports whether anyone sat out', () {
      final presence = SessionPresence.fromTracks(
        {
          'starter': track(120, (t) => (20, 10)),
          'substitute': track(120, (t) => t < 60 ? (20, -0.5) : (20, 10)),
        },
        court: court,
      );

      expect(presence.forTag('starter').stintCount, 1);
      expect(presence.forTag('substitute').benchDuration,
          const Duration(seconds: 60));
      expect(presence.hasBenchTime, isTrue);
      expect(presence.forTag('unknown-tag').stints, isEmpty,
          reason: 'an untracked tag reads as empty rather than throwing');
    });
  });
}
