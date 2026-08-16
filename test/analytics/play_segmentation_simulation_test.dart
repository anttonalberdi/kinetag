import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/play_metrics.dart';
import 'package:kinetag/src/analytics/possession.dart';
import 'package:kinetag/src/analytics/session_metrics.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/tracking/simulator/match_simulation.dart';
import 'package:kinetag/src/tracking/simulator/simulated_squad.dart';

/// The segmentation against a simulated match rather than against hand-built
/// trajectories.
///
/// The unit tests elsewhere feed the engine exactly the signal it looks for.
/// This one feeds it a match: keepers who drift around their line for reasons
/// unrelated to possession, substitutes who walk off and on, and a formation
/// that swings between ends. It is the test that would fail if the goalkeeper
/// indicator were too weak to find in real movement, which is the whole risk
/// the approach carries.
const int _stepMicros = 50000; // 20 Hz
const int _startMicros = 1786000000000000;
const double _matchSeconds = 300;

/// A seven-a-side roster per team, so each side has one substitute to rotate.
({List<Player> players, List<Tag> tags, List<TagAssignment> assignments})
    buildRoster() {
  final players = <Player>[];
  final tags = <Tag>[];
  final assignments = <TagAssignment>[];
  var index = 0;

  for (final side in TeamSide.values) {
    for (final role in PlayerRole.values) {
      index++;
      final id = 'p$index';
      final tagId = 'tag-${index.toString().padLeft(2, '0')}';
      players.add(Player(
        id: id,
        name: '${side.displayName} ${role.shortName}',
        number: index,
        team: side.displayName,
        side: side,
        role: role,
      ));
      tags.add(Tag(id: tagId, hardwareId: tagId, name: tagId));
      assignments
          .add(TagAssignment(id: 'a$index', playerId: id, tagId: tagId));
    }
  }

  return (players: players, tags: tags, assignments: assignments);
}

void main() {
  final roster = buildRoster();
  final court = Court.handball();

  final simulation = MatchSimulation(
    court: court,
    squad: SimulatedSquad.fromRoster(
      players: roster.players,
      tags: roster.tags,
      assignments: roster.assignments,
    ),
    seed: 20260816,
    substitutionInterval: const Duration(seconds: 60),
  );

  final samples = <PositionSample>[];

  /// Which side the simulation itself had attacking, per frame; null while
  /// both teams are changing ends.
  ///
  /// Recorded as the match runs rather than reconstructed afterwards, so this
  /// test measures the inference against what actually happened rather than
  /// against a second model of it.
  final truth = <int, TeamSide?>{};

  final steps = (_matchSeconds * 1e6 / _stepMicros).round();
  for (var i = 1; i <= steps; i++) {
    final at = _startMicros + i * _stepMicros;
    samples.addAll(
      simulation.advance(dtMicros: _stepMicros, timestampMicros: at).samples,
    );
    truth[at] = simulation.attackingSide;
  }

  final session = Session(
    id: 'simulated',
    name: 'Simulated match',
    createdAt: DateTime.fromMicrosecondsSinceEpoch(_startMicros, isUtc: true),
    court: court,
    teams: [
      for (final side in TeamSide.values)
        Team(
          side: side,
          name: side.displayName,
          colorValue: Team.colorPalette[side.index],
        ),
    ],
    tags: roster.tags,
    players: roster.players,
    tagAssignments: roster.assignments,
    status: SessionStatus.completed,
    startedAt: DateTime.fromMicrosecondsSinceEpoch(_startMicros, isUtc: true),
    stoppedAt: DateTime.fromMicrosecondsSinceEpoch(
      _startMicros + steps * _stepMicros,
      isUtc: true,
    ),
    sampleCount: samples.length,
  );

  final metrics = SessionPlayMetrics.from(
    metrics: SessionMetrics.fromSamples(samples),
    samples: samples,
    session: session,
  );

  group('the bench', () {
    test('the substitutes are found without being told about them', () {
      expect(metrics.hasBenchTime, isTrue);
      expect(metrics.totalBenchTime, greaterThan(const Duration(minutes: 1)));
    });

    test('the rotation is seen as several stints, not one', () {
      // Every side substitutes once a minute over five minutes, so somebody
      // must have come on more than once.
      expect(
        metrics.byTagId.values.where((p) => p.stintCount > 1),
        isNotEmpty,
      );
    });

    test('the goalkeepers are never substituted', () {
      for (final side in TeamSide.values) {
        final keeper = metrics.byTagId.values.firstWhere(
          (p) =>
              session.playerForTag(p.tagId)?.role == PlayerRole.goalkeeper &&
              session.playerForTag(p.tagId)?.side == side,
        );
        expect(keeper.benchDuration, Duration.zero,
            reason: '${side.displayName} keeper should play the whole match');
      }
    });

    test('nobody is credited with more playing time than was recorded', () {
      for (final player in metrics.byTagId.values) {
        expect(player.onCourtDuration, lessThanOrEqualTo(player.trackedDuration));
        expect(
          player.onCourtDuration + player.benchDuration,
          player.trackedDuration,
        );
      }
    });
  });

  group('attack and defence', () {
    test('the phase is recoverable from the goalkeepers alone', () {
      expect(metrics.hasPhases, isTrue);
      expect(metrics.possession.keeperSides,
          {TeamSide.home, TeamSide.away});
    });

    test('the inferred phase agrees with the match it came from', () {
      // Judged only on the settled part of each possession. The moments a
      // team is changing ends are genuinely undecided, and an indicator that
      // reads a keeper's reaction necessarily lags the turnover that caused
      // it, so disagreement there is the method working as described.
      var decided = 0;
      var agreed = 0;

      truth.forEach((at, attacking) {
        if (attacking == null) return;
        decided++;
        if (metrics.possession.attackingAt(at) == attacking) agreed++;
      });

      expect(decided, greaterThan(1000), reason: 'enough moments to judge on');
      expect(agreed / decided, greaterThan(0.8));
    });

    test('neither side is reported as attacking all match', () {
      final home =
          metrics.possession.teamTimeIn(TeamSide.home, PlayPhase.attacking);
      final away =
          metrics.possession.teamTimeIn(TeamSide.away, PlayPhase.attacking);

      expect(home.inSeconds, closeTo(away.inSeconds, 60));
    });

    test('a field player has both attacking and defending time', () {
      final pivot = metrics.byTagId.values.firstWhere(
        (p) => session.playerForTag(p.tagId)?.role == PlayerRole.centreBack,
      );

      expect(pivot.hasPhaseSplit, isTrue);
      expect(pivot.forSplit(PlaySplit.attacking).distanceMeters,
          greaterThan(0));
      expect(pivot.forSplit(PlaySplit.defending).distanceMeters,
          greaterThan(0));
    });

    test('the phases partition each player\'s playing time', () {
      for (final player in metrics.byTagId.values) {
        final parts = player.forSplit(PlaySplit.attacking).trackedDuration +
            player.forSplit(PlaySplit.defending).trackedDuration +
            player.forSplit(PlaySplit.unclear).trackedDuration;

        expect(
          (parts - player.forSplit(PlaySplit.onCourt).trackedDuration)
              .inMilliseconds
              .abs(),
          lessThan(1000),
          reason: '${player.tagId} splits should sum to its playing time',
        );
      }
    });
  });

  group('what the split changes', () {
    test('a substitute covers less ground but not less per minute', () {
      final rotated = metrics.byTagId.values
          .where((p) => p.benchDuration > const Duration(seconds: 30))
          .toList();
      expect(rotated, isNotEmpty);

      for (final player in rotated) {
        final whole = player.forSplit(PlaySplit.all);
        final playing = player.forSplit(PlaySplit.onCourt);

        expect(playing.trackedDuration, lessThan(whole.trackedDuration));
        expect(playing.averageSpeedMps, greaterThan(whole.averageSpeedMps),
            reason: 'bench time depresses the whole-recording average');
      }
    });
  });
}
