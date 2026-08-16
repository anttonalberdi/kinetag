import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/tracking/simulator/simulated_squad.dart';

void main() {
  final squad = SimulatedSquad.handballTeams();

  group('roster', () {
    test('fields two teams of six', () {
      expect(squad.participants, hasLength(12));
      expect(squad.forTeam(SimulatedTeam.home), hasLength(6));
      expect(squad.forTeam(SimulatedTeam.away), hasLength(6));
    });

    test('every role appears once per team', () {
      for (final team in SimulatedTeam.values) {
        final roles = squad.forTeam(team).map((p) => p.role).toSet();
        expect(roles, PlayerRole.values.toSet());
      }
    });

    test('player, tag and hardware identifiers are unique', () {
      expect(squad.players.map((p) => p.id).toSet(), hasLength(12));
      expect(squad.tags.map((t) => t.id).toSet(), hasLength(12));
      expect(squad.tags.map((t) => t.hardwareId).toSet(), hasLength(12));
    });

    test('shirt numbers are unique within a team', () {
      for (final team in SimulatedTeam.values) {
        final numbers = squad.forTeam(team).map((p) => p.player.number).toSet();
        expect(numbers, hasLength(6));
      }
    });
  });

  group('assignments', () {
    test('bind each tag to its own player', () {
      for (final participant in squad.participants) {
        expect(participant.assignment.tagId, participant.tag.id);
        expect(participant.assignment.playerId, participant.player.id);
      }
      expect(squad.assignments, hasLength(12));
    });

    test('resolve a tag back to its participant', () {
      final target = squad.participants[7];
      expect(squad.participantForTag(target.tag.id), same(target));
      expect(squad.participantForTag('not-a-tag'), isNull);
    });
  });

  test('role survives in player metadata for recorded sessions', () {
    // Once a session is stored the simulator is gone; the role must still be
    // recoverable from the snapshot.
    for (final participant in squad.participants) {
      expect(participant.player.metadata['role'], participant.role.name);
    }
  });

  test('roles are ordered goalkeeper first', () {
    // The live view lists players in role order; a goalkeeper heading each
    // team keeps that list readable.
    expect(PlayerRole.values.first, PlayerRole.goalkeeper);
  });
}
