import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/tracking/simulator/match_simulation.dart';
import 'package:kinetag/src/tracking/simulator/role_movement.dart';
import 'package:kinetag/src/tracking/simulator/simulation_options.dart';
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
    frames.add(
      simulation.advance(
        dtMicros: _twentyHzMicros,
        timestampMicros: i * _twentyHzMicros,
      ),
    );
  }
  return frames;
}

/// All samples for one tag, in time order.
List<PositionSample> trackOf(List<PositionFrame> frames, String tagId) => [
  for (final f in frames) f.sampleForTag(tagId)!,
];

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
            lessThanOrEqualTo(participant.movement.maxSpeedMps + 0.01),
            reason: '${participant.role!.displayName} moved too fast',
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
        expect(
          distance,
          greaterThan(20.0),
          reason: '${participant.role!.displayName} barely moved',
        );
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
          .forSide(TeamSide.home)
          .firstWhere((p) => p.role == PlayerRole.goalkeeper);
      final away = squad
          .forSide(TeamSide.away)
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
        // One full settled-attack/transition cycle is 50 seconds; sixty also
        // confirms that the next possession holds its shape.
        60,
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

      double centroidX(PositionFrame frame, TeamSide side) {
        final ids = squad.forSide(side).map((p) => p.tagId).toSet();
        final xs = frame.samples
            .where((s) => ids.contains(s.tagId))
            .map((s) => s.x)
            .toList();
        return xs.reduce((a, b) => a + b) / xs.length;
      }

      for (final frame in frames) {
        expect(
          centroidX(frame, TeamSide.home),
          lessThan(centroidX(frame, TeamSide.away)),
        );
      }
    });
  });

  group('possessions and transitions', () {
    test('each settled attack lasts twenty seconds before transition', () {
      final simulation = makeSimulation();

      expect(simulation.playPhase, 1.0);
      expect(simulation.attackingSide, TeamSide.home);

      run(simulation, 19.5);
      expect(simulation.playPhase, 1.0);
      expect(simulation.attackingSide, TeamSide.home);

      run(simulation, 1.0);
      expect(simulation.playPhase, lessThan(1.0));
      expect(simulation.attackingSide, isNull);

      run(simulation, 4.5);
      expect(simulation.playPhase, -1.0);
      expect(simulation.attackingSide, TeamSide.away);
    });

    test('wingers change ends ahead of the backs and playmaker', () {
      final squad = SimulatedSquad.handballTeams();
      final simulation = MatchSimulation(
        court: court,
        squad: squad,
        seed: 71,
        crossesPerAttack: 0,
      );
      final before = run(simulation, 20).last;
      final during = run(simulation, 3).last;
      final home = squad.forSide(TeamSide.home);
      final wing = home.firstWhere((p) => p.role == PlayerRole.leftWing);
      final playmaker = home.firstWhere((p) => p.role == PlayerRole.centreBack);

      final wingProgress =
          before.sampleForTag(wing.tagId)!.x -
          during.sampleForTag(wing.tagId)!.x;
      final playmakerProgress =
          before.sampleForTag(playmaker.tagId)!.x -
          during.sampleForTag(playmaker.tagId)!.x;

      expect(wingProgress, greaterThan(playmakerProgress));
    });

    test('cross recurrence can enable or disable attacking lane swaps', () {
      final fixed = MatchSimulation(
        court: court,
        squad: SimulatedSquad.handballTeams(),
        seed: 73,
        crossesPerAttack: 0,
      );
      final crossing = MatchSimulation(
        court: court,
        squad: SimulatedSquad.handballTeams(),
        seed: 73,
        crossesPerAttack: 3,
      );

      run(fixed, 100);
      run(crossing, 100);

      expect(fixed.crossCount, 0);
      expect(crossing.crossCount, greaterThan(0));
    });
  });

  group('the goal areas', () {
    final goalArea = GoalArea(court);

    test('nobody but the goalkeepers ever enters one', () {
      // A rule, not a tendency: an outfield player standing in the 6 m zone is
      // a free throw against, so a simulated match must not produce one.
      final squad = SimulatedSquad.handballTeams();
      final frames = run(
        MatchSimulation(court: court, squad: squad, seed: 29),
        180,
      );

      final outfield = squad.participants
          .where((p) => p.role != PlayerRole.goalkeeper)
          .map((p) => p.tagId)
          .toSet();

      for (final frame in frames) {
        for (final sample in frame.samples) {
          if (!outfield.contains(sample.tagId)) continue;
          expect(
            goalArea.contains(sample.x, sample.y),
            isFalse,
            reason:
                '${sample.tagId} stood in a goal area at '
                '(${sample.x.toStringAsFixed(2)}, '
                '${sample.y.toStringAsFixed(2)})',
          );
        }
      }
    });

    test('the goalkeepers do stand in theirs', () {
      // The exclusion must not be so eager that it empties the goal as well:
      // a keeper who never stood on their own line would be no keeper.
      final squad = SimulatedSquad.handballTeams();
      final frames = run(
        MatchSimulation(court: court, squad: squad, seed: 31),
        60,
      );

      for (final keeper in squad.participants.where(
        (p) => p.role == PlayerRole.goalkeeper,
      )) {
        final track = trackOf(frames, keeper.tagId);
        expect(
          track.any((s) => goalArea.contains(s.x, s.y)),
          isTrue,
          reason: '${keeper.side.displayName} keeper never kept goal',
        );
      }
    });

    test('play still reaches the edge of the zone', () {
      // Held out of the area, not held away from it: an attack that stopped
      // ten metres out would make the exclusion cost more than it is worth.
      final squad = SimulatedSquad.handballTeams();
      final frames = run(
        MatchSimulation(court: court, squad: squad, seed: 37),
        120,
      );

      final outfield = squad.participants
          .where((p) => p.role != PlayerRole.goalkeeper)
          .map((p) => p.tagId)
          .toSet();

      final approached = [
        for (final frame in frames)
          for (final sample in frame.samples)
            if (outfield.contains(sample.tagId) &&
                goalArea.contains(sample.x, sample.y, margin: 1.5))
              sample,
      ];
      expect(
        approached,
        isNotEmpty,
        reason: 'nobody came within 1.5 m of a goal area all match',
      );
    });
  });

  group('the bench', () {
    /// A 1 + 4 line-up out of the default six, so one substitute per side
    /// sits: the goalkeeper and four field players play, the pivot waits.
    ///
    /// Rotation off, because these are about what a bench *is*; what happens
    /// when it turns over is the group below.
    MatchSimulation benchedSimulation() => MatchSimulation(
      court: court,
      squad: SimulatedSquad.handballTeams(fieldPlayersOnCourt: 4),
      seed: 7,
      substitutionInterval: Duration.zero,
    );

    test(
      'both benches share the selected sideline, four metres from centre',
      () {
        final simulation = benchedSimulation();

        expect(simulation.benchSeatAt(TeamSide.home, 0), (
          20.0 - MatchSimulation.benchCentreGapMeters,
          20.5,
        ));
        expect(simulation.benchSeatAt(TeamSide.away, 0), (
          20.0 + MatchSimulation.benchCentreGapMeters,
          20.5,
        ));
        expect(MatchSimulation.benchCentreGapMeters, 4.0);

        final top = MatchSimulation(
          court: court,
          squad: SimulatedSquad.handballTeams(fieldPlayersOnCourt: 4),
          benchSideline: BenchSideline.top,
        );
        expect(top.benchSeatAt(TeamSide.home, 0).$2, -0.5);
        expect(top.benchSeatAt(TeamSide.away, 0).$2, -0.5);
      },
    );

    test('substitutes stand next to each other on their own half', () {
      final simulation = benchedSimulation();

      for (final side in TeamSide.values) {
        final first = simulation.benchSeatAt(side, 0);
        final second = simulation.benchSeatAt(side, 1);

        expect(
          (second.$1 - first.$1).abs(),
          closeTo(MatchSimulation.benchSpacingMeters, 1e-9),
        );
        expect(second.$2, first.$2, reason: 'a bench is a straight line');
        // Home defends x = 0, so its bench runs back from the centre line
        // toward its own goal; away's mirrors it.
        expect(
          side == TeamSide.home ? second.$1 < first.$1 : second.$1 > first.$1,
          isTrue,
        );
      }
    });

    test('a substitute stays on the bench for the whole match', () {
      final simulation = benchedSimulation();
      final benched = simulation.squad.benched.toList();
      expect(benched, hasLength(2), reason: 'one substitute per side');

      final frames = run(simulation, 120);

      for (final participant in benched) {
        final seat = simulation.benchSeatAt(
          participant.side,
          participant.benchSeat!,
        );
        for (final sample in trackOf(frames, participant.tagId)) {
          expect(sample.x, closeTo(seat.$1, 1e-9));
          expect(sample.y, closeTo(seat.$2, 1e-9));
        }
      }
    });

    test('a substitute covers no ground, which is what marks them out', () {
      // The analytics downstream have no notion of a bench; a flat track is
      // the whole signal that this player did not play.
      final simulation = benchedSimulation();
      final frames = run(simulation, 60);

      for (final participant in simulation.squad.benched) {
        final track = trackOf(frames, participant.tagId);
        var distance = 0.0;
        for (var i = 1; i < track.length; i++) {
          distance += math.sqrt(
            math.pow(track[i].x - track[i - 1].x, 2) +
                math.pow(track[i].y - track[i - 1].y, 2),
          );
        }
        expect(distance, closeTo(0, 1e-6));
      }
    });

    test('the players who are fielded still play a normal match', () {
      // Benching somebody must not shrink the game to a huddle.
      final simulation = benchedSimulation();
      final frames = run(simulation, 60);

      for (final participant in simulation.squad.onCourt) {
        final track = trackOf(frames, participant.tagId);
        for (final sample in track) {
          expect(sample.x, inInclusiveRange(0, court.widthMeters));
          expect(sample.y, inInclusiveRange(0, court.heightMeters));
        }

        var distance = 0.0;
        for (var i = 1; i < track.length; i++) {
          distance += math.sqrt(
            math.pow(track[i].x - track[i - 1].x, 2) +
                math.pow(track[i].y - track[i - 1].y, 2),
          );
        }
        expect(
          distance,
          greaterThan(5.0),
          reason: '${participant.tagId} should be moving',
        );
      }
    });
  });

  group('substitutions', () {
    /// A 1 + 4 line-up out of the default six — five on court per side, the
    /// pivot on the bench — rotating every half minute, so a couple of minutes
    /// of simulated match contains several exchanges.
    MatchSimulation rotatingSimulation({
      int seed = 7,
      Duration every = const Duration(seconds: 30),
    }) => MatchSimulation(
      court: court,
      squad: SimulatedSquad.handballTeams(fieldPlayersOnCourt: 4),
      seed: seed,
      substitutionInterval: every,
    );

    /// Whether a sample is on the floor of play, as opposed to on its way to
    /// or from the bench outside the sideline.
    bool onPlayingSurface(PositionSample sample) =>
        sample.x >= 0 &&
        sample.x <= court.widthMeters &&
        sample.y >= 0 &&
        sample.y <= court.heightMeters;

    List<PositionSample> forSide(
      PositionFrame frame,
      SimulatedSquad squad,
      TeamSide side,
    ) => [
      for (final sample in frame.samples)
        if (squad.participantForTag(sample.tagId)!.side == side) sample,
    ];

    test('a substitute comes on and the player they replace goes off', () {
      final simulation = rotatingSimulation();
      final substitute = simulation.squad.benched.first;
      final starters = simulation.squad.onCourt.toList();

      expect(simulation.isOnCourt(substitute.tagId), isFalse);

      run(simulation, 60);

      expect(
        simulation.isOnCourt(substitute.tagId),
        isTrue,
        reason: 'the bench never emptied',
      );
      expect(
        starters.where((p) => !simulation.isOnCourt(p.tagId)),
        isNotEmpty,
        reason: 'somebody must have made room',
      );
    });

    test('the substitute waits until their team-mate is off the court', () {
      // The requirement the whole handover exists for: a side that briefly had
      // both of them on would be playing a player up, and every team metric
      // over that window — count, centroid, width — would be wrong.
      final simulation = rotatingSimulation(seed: 19);
      final squad = simulation.squad;
      final frames = run(simulation, 180);

      for (final frame in frames) {
        for (final side in TeamSide.values) {
          final playing = forSide(
            frame,
            squad,
            side,
          ).where(onPlayingSurface).length;
          expect(
            playing,
            lessThanOrEqualTo(5),
            reason: '${side.displayName} fielded an extra player',
          );
        }
      }
    });

    test('a side is briefly a player short while the exchange happens', () {
      // The other half of the same guarantee: if the count never dipped, the
      // "walk off first" sequencing would be decorative and the test above
      // would pass on a simulation that swapped the two instantaneously.
      final simulation = rotatingSimulation(seed: 19);
      final squad = simulation.squad;
      final frames = run(simulation, 180);

      final shortHanded = [
        for (final frame in frames)
          for (final side in TeamSide.values)
            if (forSide(frame, squad, side).where(onPlayingSurface).length < 5)
              side,
      ];
      expect(shortHanded, isNotEmpty);
    });

    test('the player who came off ends up standing at a bench seat', () {
      final simulation = rotatingSimulation(seed: 23);
      // Stopped between two exchanges rather than on one, so nobody is caught
      // mid-walk: what is being checked is where they end up, not how long the
      // walk takes.
      final frames = run(simulation, 110);

      final seated = simulation.squad.participants.where(
        (p) => !simulation.isOnCourt(p.tagId),
      );
      expect(seated, isNotEmpty);

      for (final participant in seated) {
        final last = trackOf(frames, participant.tagId).last;
        final seats = [
          for (var seat = 0; seat < simulation.squad.length; seat++)
            simulation.benchSeatAt(participant.side, seat),
        ];
        expect(
          seats.any(
            (s) =>
                (s.$1 - last.x).abs() < MatchSimulation.benchArrivalMeters &&
                (s.$2 - last.y).abs() < MatchSimulation.benchArrivalMeters,
          ),
          isTrue,
          reason: '${participant.tagId} is off but not at the bench',
        );
      }
    });

    test('a substitute who comes on plays, and at their new role’s pace', () {
      final simulation = rotatingSimulation(seed: 41);
      final substitute = simulation.squad.benched.first;
      final frames = run(simulation, 120);
      final track = trackOf(frames, substitute.tagId);

      var distance = 0.0;
      var fastest = 0.0;
      for (var i = 1; i < track.length; i++) {
        distance += track[i - 1].distanceTo(track[i]);
        fastest = math.max(fastest, track[i - 1].speedTo(track[i]));
      }

      // They walked off the bench and played, rather than sitting all match…
      expect(distance, greaterThan(50.0));
      // …at the speed of the slot they took over, not the bench's walking pace
      // and not faster than any role on the court can run.
      expect(fastest, greaterThan(RoleMovement.benched.maxSpeedMps));
      expect(fastest, lessThanOrEqualTo(7.5 + 0.01));
    });

    test('goalkeepers are never substituted', () {
      // A side that exchanged its keeper would have an empty goal for as long
      // as the walk took.
      final simulation = rotatingSimulation(seed: 43);
      run(simulation, 180);

      for (final keeper in simulation.squad.participants.where(
        (p) => p.role == PlayerRole.goalkeeper,
      )) {
        expect(simulation.isOnCourt(keeper.tagId), isTrue);
      }
    });

    test('the rotation keeps its cadence, both sides at once', () {
      final simulation = rotatingSimulation(seed: 47);
      run(simulation, 125);

      // Four windows of 30 s, two sides, minus whatever exchange was still a
      // walk in progress when the clock stopped.
      expect(simulation.substitutionCount, greaterThanOrEqualTo(6));
      expect(simulation.substitutionCount, lessThanOrEqualTo(8));
    });

    test('an interval of zero leaves the starting line-up alone', () {
      final simulation = rotatingSimulation(every: Duration.zero);
      final substitute = simulation.squad.benched.first;

      run(simulation, 180);

      expect(simulation.substitutionCount, 0);
      expect(simulation.isOnCourt(substitute.tagId), isFalse);
    });

    test('a full bench has nobody to bring on', () {
      // Every tag in the default squad is fielded, so the rotation has nothing
      // to do and must not manufacture something.
      final simulation = MatchSimulation(
        court: court,
        squad: SimulatedSquad.handballTeams(),
        seed: 7,
        substitutionInterval: const Duration(seconds: 30),
      );
      run(simulation, 180);

      expect(simulation.substitutionCount, 0);
      for (final participant in simulation.squad.participants) {
        expect(simulation.isOnCourt(participant.tagId), isTrue);
      }
    });

    test('rotating players stay on the court and out of the goal areas', () {
      // Coming on from outside the sideline is the one moment a player is
      // legitimately off the floor; it must not become a way onto it in the
      // wrong place.
      final goalArea = GoalArea(court);
      final simulation = rotatingSimulation(seed: 53);
      final squad = simulation.squad;
      final frames = run(simulation, 180);

      for (final frame in frames) {
        for (final sample in frame.samples) {
          if (!onPlayingSurface(sample)) continue;
          final participant = squad.participantForTag(sample.tagId)!;
          if (participant.role == PlayerRole.goalkeeper) continue;
          expect(goalArea.contains(sample.x, sample.y), isFalse);
        }
      }
    });

    test('the same seed replays the same rotation', () {
      final a = run(rotatingSimulation(seed: 61), 120);
      final b = run(rotatingSimulation(seed: 61), 120);

      for (var i = 0; i < a.length; i++) {
        expect(a[i].samples, b[i].samples);
      }
    });

    test('attack-only exchanges wait until that side is attacking', () {
      final simulation = MatchSimulation(
        court: court,
        squad: SimulatedSquad.handballTeams(fieldPlayersOnCourt: 4),
        seed: 67,
        substitutionInterval: const Duration(seconds: 30),
        substitutionTiming: SubstitutionTiming.whileAttacking,
      );
      final homeStarters = simulation.squad
          .forSide(TeamSide.home)
          .where((participant) => participant.isOnCourt)
          .toList();
      final awayStarters = simulation.squad
          .forSide(TeamSide.away)
          .where((participant) => participant.isOnCourt)
          .toList();

      // At 30 s away is attacking. Its due exchange starts, while home waits.
      run(simulation, 31);
      expect(homeStarters.every((p) => simulation.isOnCourt(p.tagId)), isTrue);
      expect(awayStarters.any((p) => !simulation.isOnCourt(p.tagId)), isTrue);

      // Home's next settled attack begins at 50 s and releases its due call.
      run(simulation, 20);
      expect(homeStarters.any((p) => !simulation.isOnCourt(p.tagId)), isTrue);
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
