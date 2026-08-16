import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/session_metrics.dart';
import 'package:kinetag/src/analytics/speed_zones.dart';
import 'package:kinetag/src/analytics/team_metrics.dart';
import 'package:kinetag/src/domain/domain.dart';

const int kStartMicros = 1786000000000000;

/// A straight run along X at [speedMps], sampled at 20 Hz.
List<PositionSample> run({
  required String tagId,
  required double speedMps,
  double seconds = 4.0,
}) {
  const stepMicros = 50000;
  final count = (seconds * 20).round() + 1;
  return [
    for (var i = 0; i < count; i++)
      PositionSample(
        timestampMicros: kStartMicros + i * stepMicros,
        tagId: tagId,
        x: speedMps * (i * stepMicros / 1e6),
        y: 10,
      ),
  ];
}

/// A session whose players are described as `tagId -> (name, side, team)`.
Session sessionWith(List<(String, String, TeamSide?, String?)> roster) {
  final players = [
    for (final (tagId, name, side, team) in roster)
      Player(id: 'p-$tagId', name: name, side: side, team: team),
  ];

  return Session(
    id: 'session-1',
    name: 'Test',
    createdAt: DateTime.utc(2026, 8, 16),
    court: Court.handball(),
    receivers: const [],
    tags: [
      for (final (tagId, _, _, _) in roster)
        Tag(id: tagId, hardwareId: tagId, name: tagId),
    ],
    players: players,
    tagAssignments: [
      for (final (tagId, _, _, _) in roster)
        TagAssignment(id: 'a-$tagId', playerId: 'p-$tagId', tagId: tagId),
    ],
    teams: const [
      Team(side: TeamSide.home, name: 'Ajax', colorValue: 0xFF5AA9FF),
      Team(side: TeamSide.away, name: 'Feyenoord', colorValue: 0xFFFF9445),
    ],
  );
}

void main() {
  group('grouping', () {
    test('splits players by the side the session recorded', () {
      final session = sessionWith([
        ('tag-a', 'Ann', TeamSide.home, 'Ajax'),
        ('tag-b', 'Bo', TeamSide.away, 'Feyenoord'),
        ('tag-c', 'Cas', TeamSide.home, 'Ajax'),
      ]);
      final metrics = SessionTeamMetrics.from(
        session: session,
        metrics: SessionMetrics.fromSamples([
          ...run(tagId: 'tag-a', speedMps: 5),
          ...run(tagId: 'tag-b', speedMps: 3),
          ...run(tagId: 'tag-c', speedMps: 1),
        ]),
      );

      expect(metrics.teams.map((t) => t.label), ['Ajax', 'Feyenoord']);
      expect(metrics.teams.first.playerCount, 2);
      expect(metrics.teamOf('tag-c')!.label, 'Ajax');
      // Home first, whichever side ran furthest.
      expect(metrics.teams.first.side, TeamSide.home);
    });

    test('prefers the team record to a player’s own stale copy', () {
      // The player still carries the name the team had before it was renamed;
      // the session's team record is what a report must show.
      final session = sessionWith([
        ('tag-a', 'Ann', TeamSide.home, 'Old name'),
      ]);
      final metrics = SessionTeamMetrics.from(
        session: session,
        metrics: SessionMetrics.fromSamples(run(tagId: 'tag-a', speedMps: 5)),
      );

      expect(metrics.teams.single.label, 'Ajax');
    });

    test('groups by name for a session recorded before sides existed', () {
      final session = Session(
        id: 'legacy',
        name: 'Legacy',
        createdAt: DateTime.utc(2026, 8, 16),
        court: Court.handball(),
        receivers: const [],
        tags: const [
          Tag(id: 'tag-a', hardwareId: 'a', name: 'a'),
          Tag(id: 'tag-b', hardwareId: 'b', name: 'b'),
        ],
        players: const [
          Player(id: 'p-a', name: 'Ann', team: 'Reds'),
          Player(id: 'p-b', name: 'Bo', team: 'Blues'),
        ],
        tagAssignments: const [
          TagAssignment(id: '1', playerId: 'p-a', tagId: 'tag-a'),
          TagAssignment(id: '2', playerId: 'p-b', tagId: 'tag-b'),
        ],
      );
      final metrics = SessionTeamMetrics.from(
        session: session,
        metrics: SessionMetrics.fromSamples([
          ...run(tagId: 'tag-a', speedMps: 5),
          ...run(tagId: 'tag-b', speedMps: 3),
        ]),
      );

      expect(metrics.teams.map((t) => t.label), ['Blues', 'Reds']);
      expect(metrics.teams.every((t) => t.side == null), isTrue);
    });

    test('puts tags with no wearer in their own group, last', () {
      final session = sessionWith([('tag-a', 'Ann', TeamSide.home, 'Ajax')]);
      final metrics = SessionTeamMetrics.from(
        session: session,
        metrics: SessionMetrics.fromSamples([
          ...run(tagId: 'tag-a', speedMps: 5),
          ...run(tagId: 'tag-loose', speedMps: 2),
        ]),
      );

      expect(metrics.teams.map((t) => t.label), [
        'Ajax',
        SessionTeamMetrics.unassignedLabel,
      ]);
      expect(metrics.teams.last.tracks.single.tagId, 'tag-loose');
    });
  });

  group('aggregates', () {
    test('totals and averages are the sum and mean of the tracks', () {
      // 5 m/s and 1 m/s for 4 s: 20 m and 4 m on the same side.
      final session = sessionWith([
        ('tag-a', 'Ann', TeamSide.home, 'Ajax'),
        ('tag-c', 'Cas', TeamSide.home, 'Ajax'),
      ]);
      final metrics = SessionTeamMetrics.from(
        session: session,
        metrics: SessionMetrics.fromSamples([
          ...run(tagId: 'tag-a', speedMps: 5),
          ...run(tagId: 'tag-c', speedMps: 1),
        ]),
      );
      final team = metrics.teams.single;

      expect(team.totalDistanceMeters, closeTo(24.0, 1e-6));
      expect(team.averageDistanceMeters, closeTo(12.0, 1e-6));
      expect(team.averageSpeedMps, closeTo(3.0, 1e-6));
      expect(team.maxSpeedMps, closeTo(5.0, 1e-6));
      expect(team.fastest!.tagId, 'tag-a');

      expect(metrics.totalDistanceMeters, closeTo(24.0, 1e-6));
      expect(metrics.averageDistanceMeters, closeTo(12.0, 1e-6));
      expect(metrics.fastest!.tagId, 'tag-a');
      expect(metrics.trackedDuration, const Duration(seconds: 4));
    });

    test('ranks every player by distance across teams', () {
      final session = sessionWith([
        ('tag-a', 'Ann', TeamSide.home, 'Ajax'),
        ('tag-b', 'Bo', TeamSide.away, 'Feyenoord'),
      ]);
      final metrics = SessionTeamMetrics.from(
        session: session,
        metrics: SessionMetrics.fromSamples([
          ...run(tagId: 'tag-a', speedMps: 1),
          ...run(tagId: 'tag-b', speedMps: 5),
        ]),
      );

      expect(metrics.ranked.map((t) => t.tagId), ['tag-b', 'tag-a']);
      expect(metrics.rankOf('tag-b'), 1);
      expect(metrics.rankOf('tag-a'), 2);
      expect(metrics.rankOf('nobody'), 0);
    });

    test('team intensity is its players’ bands added together', () {
      // Both run at 5 m/s, which is the running band, for 4 s each.
      final session = sessionWith([
        ('tag-a', 'Ann', TeamSide.home, 'Ajax'),
        ('tag-c', 'Cas', TeamSide.home, 'Ajax'),
      ]);
      final metrics = SessionTeamMetrics.from(
        session: session,
        metrics: SessionMetrics.fromSamples([
          ...run(tagId: 'tag-a', speedMps: 5),
          ...run(tagId: 'tag-c', speedMps: 5),
        ]),
      );

      final team = metrics.teams.single;
      final own = metrics.zonesByTag['tag-a']!.inZone(SpeedZone.running);

      expect(team.zones.inZone(SpeedZone.running), own * 2);
      expect(metrics.timeIn(SpeedZone.running), own * 2);
      expect(team.zones.shareOf(SpeedZone.running), closeTo(1.0, 1e-9));
    });

    test(
      'an empty recording reports nothing rather than zeroes everywhere',
      () {
        final metrics = SessionTeamMetrics.from(
          session: sessionWith([('tag-a', 'Ann', TeamSide.home, 'Ajax')]),
          metrics: SessionMetrics.fromSamples(const []),
        );

        expect(metrics.isEmpty, isTrue);
        expect(metrics.teams, isEmpty);
        expect(metrics.fastest, isNull);
        expect(metrics.totalDistanceMeters, 0);
        expect(metrics.trackedDuration, Duration.zero);
      },
    );
  });
}
