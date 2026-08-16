import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/tracking/simulator/match_simulation.dart';
import 'package:kinetag/src/tracking/simulator/simulated_squad.dart';

const int _twentyHzMicros = 50000;

MatchSimulation makeSimulation({int seed = 7}) => MatchSimulation(
      court: Court.handball(),
      squad: SimulatedSquad.handballTeams(),
      seed: seed,
    );

/// Runs [seconds] of simulated match at 20 Hz and returns every frame.
List<PositionFrame> run(MatchSimulation simulation, double seconds) {
  final frames = <PositionFrame>[];
  final steps = (seconds * 1e6 / _twentyHzMicros).round();
  for (var i = 1; i <= steps; i++) {
    frames.add(simulation.advance(
      dtMicros: _twentyHzMicros,
      timestampMicros: i * _twentyHzMicros,
    ));
  }
  return frames;
}

/// All samples for one tag, in time order.
List<PositionSample> trackOf(List<PositionFrame> frames, String tagId) =>
    [for (final f in frames) f.sampleForTag(tagId)!];

void main() {
  final court = Court.handball();

  group('frames', () {
    test('carry one sample per tag, stamped with the frame time', () {
      final simulation = makeSimulation();
      final frame = simulation.advance(
        dtMicros: _twentyHzMicros,
        timestampMicros: 1234567,
      );

      expect(frame.samples, hasLength(12));
      expect(frame.tagIds.toSet(), hasLength(12));
      expect(frame.timestampMicros, 1234567);
      for (final sample in frame.samples) {
        expect(sample.timestampMicros, 1234567);
      }
    });

    test('report a confidence in 0..1', () {
      for (final frame in run(makeSimulation(), 20)) {
        for (final sample in frame.samples) {
          expect(sample.confidence, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });

  group('determinism', () {
    test('the same seed replays the same match exactly', () {
      final a = run(makeSimulation(seed: 42), 30);
      final b = run(makeSimulation(seed: 42), 30);

      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].samples, b[i].samples);
      }
    });

    test('a different seed produces a different match', () {
      final a = run(makeSimulation(seed: 1), 30).last.samples;
      final b = run(makeSimulation(seed: 2), 30).last.samples;
      expect(a, isNot(b));
    });
  });

  group('physical plausibility', () {
    test('players never leave the court', () {
      for (final frame in run(makeSimulation(), 120)) {
        for (final sample in frame.samples) {
          expect(sample.x, inInclusiveRange(0.0, court.widthMeters));
          expect(sample.y, inInclusiveRange(0.0, court.heightMeters));
        }
      }
    });

    test('nobody exceeds their role sprint speed', () {
      final squad = SimulatedSquad.handballTeams();
      final frames = run(
        MatchSimulation(court: court, squad: squad, seed: 3),
        120,
      );

      for (final participant in squad.participants) {
        final track = trackOf(frames, participant.tagId);
        for (var i = 1; i < track.length; i++) {
          expect(
            track[i - 1].speedTo(track[i]),
            // A hair of slack: velocity is integrated at the step boundary.
            lessThanOrEqualTo(participant.role.maxSpeedMps + 0.01),
            reason: '${participant.role.displayName} moved too fast',
          );
        }
      }
    });

    test('motion is smooth — acceleration stays within human limits', () {
      // Steering is acceleration-limited, so no frame-to-frame teleporting.
      final frames = run(makeSimulation(seed: 11), 60);
      final tagId = frames.first.samples[4].tagId;
      final track = trackOf(frames, tagId);
      const dt = _twentyHzMicros / 1e6;

      for (var i = 2; i < track.length; i++) {
        final v1 = _velocity(track[i - 2], track[i - 1], dt);
        final v2 = _velocity(track[i - 1], track[i], dt);
        final acceleration =
            math.sqrt(math.pow(v2.$1 - v1.$1, 2) + math.pow(v2.$2 - v1.$2, 2)) /
                dt;
        expect(acceleration, lessThan(8.0));
      }
    });

    test('everyone actually moves a plausible match distance', () {
      final squad = SimulatedSquad.handballTeams();
      final frames = run(
        MatchSimulation(court: court, squad: squad, seed: 5),
        120,
      );

      for (final participant in squad.participants) {
        final track = trackOf(frames, participant.tagId);
        var distance = 0.0;
        for (var i = 1; i < track.length; i++) {
          distance += track[i - 1].distanceTo(track[i]);
        }
        // Two minutes of handball: tens of metres at minimum, even in goal.
        expect(distance, greaterThan(20.0),
            reason: '${participant.role.displayName} barely moved');
      }
    });
  });

  group('role behaviour', () {
    test('trajectories differ from player to player', () {
      final frames = run(makeSimulation(seed: 9), 60);
      final last = frames.last.samples;

      // No two players occupy the same point, and the spread is court-wide
      // rather than a huddle.
      final points = last.map((s) => (s.x, s.y)).toSet();
      expect(points, hasLength(last.length));
      final xs = last.map((s) => s.x);
      expect(xs.reduce(math.max) - xs.reduce(math.min), greaterThan(10.0));
    });

    test('goalkeepers stay near their own goal', () {
      final squad = SimulatedSquad.handballTeams();
      final frames = run(
        MatchSimulation(court: court, squad: squad, seed: 13),
        180,
      );

      final home = squad
          .forTeam(SimulatedTeam.home)
          .firstWhere((p) => p.role == PlayerRole.goalkeeper);
      final away = squad
          .forTeam(SimulatedTeam.away)
          .firstWhere((p) => p.role == PlayerRole.goalkeeper);

      for (final sample in trackOf(frames, home.tagId)) {
        expect(sample.x, lessThan(10.0));
      }
      for (final sample in trackOf(frames, away.tagId)) {
        expect(sample.x, greaterThan(court.widthMeters - 10.0));
      }
    });

    test('play swings between both ends of the court', () {
      // The formation must travel, otherwise team metrics are a flat line.
      final squad = SimulatedSquad.handballTeams();
      final frames = run(
        MatchSimulation(court: court, squad: squad, seed: 17),
        // One full attack/defence period.
        40,
      );
      final outfield = squad.participants
          .where((p) => p.role != PlayerRole.goalkeeper)
          .map((p) => p.tagId)
          .toSet();

      final centroids = [
        for (final frame in frames)
          frame.samples
                  .where((s) => outfield.contains(s.tagId))
                  .map((s) => s.x)
                  .reduce((a, b) => a + b) /
              outfield.length,
      ];

      final swing = centroids.reduce(math.max) - centroids.reduce(math.min);
      expect(swing, greaterThan(10.0));
    });

    test('the two teams stay on opposite sides of the ball', () {
      // Home and away formations travel together, not through each other:
      // their centroids should remain distinguishable.
      final squad = SimulatedSquad.handballTeams();
      final simulation = MatchSimulation(court: court, squad: squad, seed: 23);
      final frames = run(simulation, 60);

      double centroidX(PositionFrame frame, SimulatedTeam team) {
        final ids = squad.forTeam(team).map((p) => p.tagId).toSet();
        final xs = frame.samples
            .where((s) => ids.contains(s.tagId))
            .map((s) => s.x)
            .toList();
        return xs.reduce((a, b) => a + b) / xs.length;
      }

      for (final frame in frames) {
        expect(centroidX(frame, SimulatedTeam.home),
            lessThan(centroidX(frame, SimulatedTeam.away)));
      }
    });
  });

  test('elapsed time tracks the steps taken', () {
    final simulation = makeSimulation();
    run(simulation, 10);
    expect(simulation.elapsed, const Duration(seconds: 10));
  });
}

(double, double) _velocity(PositionSample a, PositionSample b, double dt) =>
    ((b.x - a.x) / dt, (b.y - a.y) / dt);
