import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';

Session buildSession() => Session(
      id: 's-1',
      name: 'Training 1',
      createdAt: DateTime.utc(2026, 8, 16, 10),
      court: Court.handball(),
      receivers: const [
        Receiver(id: 'rx-1', name: 'RX-01', x: -1.2, y: -0.8, z: 2.4),
        Receiver(id: 'rx-2', name: 'RX-02', x: 41.2, y: -0.8, z: 2.4),
      ],
      tags: const [
        Tag(id: 't-1', hardwareId: 'HW-1', name: 'Tag 1'),
      ],
      teams: const [
        Team(side: TeamSide.home, name: 'Ajax', colorValue: 0xFF67D68A),
        Team(side: TeamSide.away, name: 'Feyenoord', colorValue: 0xFFFF6B6B),
      ],
      players: const [
        Player(
          id: 'p-1',
          name: 'Ana Ruiz',
          number: 7,
          team: 'Ajax',
          side: TeamSide.home,
          role: PlayerRole.pivot,
        ),
      ],
      tagAssignments: const [
        TagAssignment(
          id: 'ta-1',
          playerId: 'p-1',
          tagId: 't-1',
          location: TagMountLocation.leftShoe,
        ),
      ],
    );

void main() {
  group('Court', () {
    test('handball court is 40 x 20 metres', () {
      final court = Court.handball();
      expect(court.widthMeters, 40.0);
      expect(court.heightMeters, 20.0);
      expect(court.sport, SportType.handball);
    });
  });

  group('Session setup snapshot', () {
    test('mutating the live setup does not alter a recorded session', () {
      // This is the core data-integrity guarantee: a session must keep the
      // anchor geometry that actually produced its trajectories.
      final session = buildSession();
      final originalX = session.receivers.first.x;

      // Simulate the setup screen moving the receiver afterwards.
      final movedReceiver = session.receivers.first.copyWith(x: 99.0);

      expect(session.receivers.first.x, originalX);
      expect(movedReceiver.x, 99.0);
      expect(session.receivers.first, isNot(movedReceiver));
    });

    test('snapshot survives a JSON round trip', () {
      final session = buildSession();
      final restored = Session.fromJson(session.toJson());

      expect(restored.id, session.id);
      expect(restored.name, session.name);
      expect(restored.createdAt, session.createdAt);
      expect(restored.court, session.court);
      expect(restored.receivers, session.receivers);
      expect(restored.tags, session.tags);
      expect(restored.players, session.players);
      expect(restored.tagAssignments, session.tagAssignments);
      expect(restored.teams, session.teams);
      expect(restored.players.first.role, PlayerRole.pivot);
      expect(restored.players.first.side, TeamSide.home);
      expect(restored.positioningAlgorithmVersion,
          session.positioningAlgorithmVersion);
    });

    test('records which positioning algorithm produced the data', () {
      expect(buildSession().positioningAlgorithmVersion, 'simulator-v1');
    });

    test('freezes the teams, so a later recolour cannot rewrite history', () {
      // Team colour is a coach's choice, and a recording must replay in the
      // colours it was captured with — the same rule as receiver geometry.
      final session = buildSession();
      final recoloured = session.teams.first.copyWith(colorValue: 0xFF000000);

      expect(session.teamFor(TeamSide.home)!.colorValue, 0xFF67D68A);
      expect(session.teamFor(TeamSide.home), isNot(recoloured));
      expect(session.teamFor(TeamSide.away)!.name, 'Feyenoord');
    });

    test('reads back a session recorded before teams existed', () {
      // Older rows have no `teams` key at all; they must still load.
      final json = Map<String, dynamic>.of(buildSession().toJson())
        ..remove('teams');
      final restored = Session.fromJson(json);

      expect(restored.teams, isEmpty);
      expect(restored.teamFor(TeamSide.home), isNull);
      expect(restored.players, hasLength(1));
    });
  });

  group('Session lookups', () {
    test('resolves the player wearing a tag', () {
      expect(buildSession().playerForTag('t-1')?.name, 'Ana Ruiz');
    });

    test('returns null for an unassigned tag', () {
      expect(buildSession().playerForTag('t-unknown'), isNull);
    });

    test('supports two assignments per player', () {
      // The prototype uses one tag per player, but the model must already
      // allow left + right shoe.
      final session = buildSession().copyWith(
        tags: const [
          Tag(id: 't-1', hardwareId: 'HW-1', name: 'Tag 1'),
          Tag(id: 't-2', hardwareId: 'HW-2', name: 'Tag 2'),
        ],
        tagAssignments: const [
          TagAssignment(
            id: 'ta-1',
            playerId: 'p-1',
            tagId: 't-1',
            location: TagMountLocation.leftShoe,
          ),
          TagAssignment(
            id: 'ta-2',
            playerId: 'p-1',
            tagId: 't-2',
            location: TagMountLocation.rightShoe,
          ),
        ],
      );

      final assignments = session.assignmentsForPlayer('p-1');
      expect(assignments, hasLength(2));
      expect(
        assignments.map((a) => a.location),
        containsAll(
            [TagMountLocation.leftShoe, TagMountLocation.rightShoe]),
      );
      expect(session.playerForTag('t-2')?.name, 'Ana Ruiz');
    });
  });

  group('Session lifecycle', () {
    test('a draft session has no duration', () {
      expect(buildSession().duration, isNull);
      expect(buildSession().status, SessionStatus.draft);
    });

    test('a completed session reports its wall-clock duration', () {
      final session = buildSession().copyWith(
        status: SessionStatus.completed,
        startedAt: DateTime.utc(2026, 8, 16, 10, 0, 0),
        stoppedAt: DateTime.utc(2026, 8, 16, 10, 5, 30),
        sampleCount: 1000,
      );

      expect(session.duration, const Duration(minutes: 5, seconds: 30));
      expect(session.hasRecordedData, isTrue);
    });

    test('a completed session with no samples has no recorded data', () {
      final session = buildSession().copyWith(
        status: SessionStatus.completed,
        sampleCount: 0,
      );
      expect(session.hasRecordedData, isFalse);
    });
  });

  group('Player', () {
    test('short label prefers the shirt number', () {
      const p = Player(id: 'p', name: 'Ana Ruiz', number: 7);
      expect(p.shortLabel, '7');
    });

    test('short label falls back to initials', () {
      const p = Player(id: 'p', name: 'Ana Ruiz');
      expect(p.shortLabel, 'AR');
    });
  });
}
