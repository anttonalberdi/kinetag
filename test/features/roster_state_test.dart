import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/setup/roster_state.dart';

({ProviderContainer container, RosterController controller}) makeController() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return (
    container: container,
    controller: container.read(rosterControllerProvider.notifier),
  );
}

RosterState readState(ProviderContainer c) => c.read(rosterControllerProvider);

void main() {
  group('default roster', () {
    test('fields two teams of six', () {
      final state = readState(makeController().container);

      expect(state.tagCount, 12);
      expect(state.forSide(TeamSide.home), hasLength(6));
      expect(state.forSide(TeamSide.away), hasLength(6));
    });

    test('gives every player a role from the standard line-up', () {
      final state = readState(makeController().container);

      for (final side in TeamSide.values) {
        expect(state.rolesTaken(side), PlayerRole.defaultLineup.toSet());
      }
    });

    test('gives every player, tag and assignment a unique id', () {
      final state = readState(makeController().container);

      expect(state.players.map((p) => p.id).toSet(), hasLength(12));
      expect(state.tags.map((t) => t.id).toSet(), hasLength(12));
      expect(state.tags.map((t) => t.hardwareId).toSet(), hasLength(12));
      expect(state.assignments.map((a) => a.id).toSet(), hasLength(12));
    });

    test('binds each assignment to its own tag and player', () {
      for (final m in readState(makeController().container).members) {
        expect(m.assignment.tagId, m.tag.id);
        expect(m.assignment.playerId, m.player.id);
      }
    });

    test('names both teams after the side they defend', () {
      final state = readState(makeController().container);

      expect(state.teamName(TeamSide.home), 'Home');
      expect(state.teamName(TeamSide.away), 'Away');
      expect(state.players.first.team, 'Home');
    });
  });

  group('adding and removing players', () {
    test('adds to the side with fewer players', () {
      final c = makeController();
      c.controller.addPlayer();

      final state = readState(c.container);
      expect(state.tagCount, 13);
      // Both sides start at six, so a tie goes to home; the next goes away.
      expect(state.forSide(TeamSide.home), hasLength(7));
      c.controller.addPlayer();
      expect(readState(c.container).forSide(TeamSide.away), hasLength(7));
    });

    test('adds to the team asked for', () {
      final c = makeController();
      c.controller.addPlayer(side: TeamSide.away);

      expect(readState(c.container).playerCount(TeamSide.away), 7);
      expect(readState(c.container).playerCount(TeamSide.home), 6);
    });

    test('suggests the first unfilled role, then falls back to any', () {
      final c = makeController();
      // Right wing is the only standard role the default line-up leaves out.
      expect(c.controller.addPlayer(side: TeamSide.home)!.role,
          PlayerRole.rightWing);
    });

    test('never reuses an identifier after a removal', () {
      final c = makeController();
      final removed = readState(c.container).members.last;
      c.controller.removePlayer(removed.playerId);
      final added = c.controller.addPlayer()!;

      expect(added.playerId, isNot(removed.playerId));
      expect(added.tagId, isNot(removed.tagId));
      expect(added.tag.hardwareId, isNot(removed.tag.hardwareId));
    });

    test('a team may be emptied entirely', () {
      // A team with no players is a legitimate intermediate state while a
      // squad is being entered; nothing downstream requires a minimum.
      final c = makeController();
      c.controller.setPlayerCount(TeamSide.away, 0);

      expect(readState(c.container).playerCount(TeamSide.away), 0);
      expect(readState(c.container).forSide(TeamSide.home), hasLength(6));
    });

    test('refuses to exceed the per-team squad limit', () {
      final c = makeController();
      c.controller.setPlayerCount(TeamSide.home, RosterState.maxPlayersPerTeam);

      expect(c.controller.addPlayer(side: TeamSide.home), isNull);
      expect(readState(c.container).playerCount(TeamSide.home),
          RosterState.maxPlayersPerTeam);
      // The other team is unaffected by its opponent being full.
      expect(c.controller.addPlayer(side: TeamSide.away), isNotNull);
    });
  });

  group('setting a team’s player count', () {
    test('grows that team only', () {
      final c = makeController();
      c.controller.setPlayerCount(TeamSide.home, 11);

      final state = readState(c.container);
      expect(state.playerCount(TeamSide.home), 11);
      expect(state.playerCount(TeamSide.away), 6);
    });

    test('shrinks by dropping the most recently added players', () {
      final c = makeController();
      final kept = readState(c.container).forSide(TeamSide.home).take(4).toList();

      c.controller.setPlayerCount(TeamSide.home, 4);

      expect(readState(c.container).forSide(TeamSide.home), kept);
    });

    test('is clamped to the squad limit', () {
      final c = makeController();

      c.controller.setPlayerCount(TeamSide.home, -5);
      expect(readState(c.container).playerCount(TeamSide.home), 0);

      c.controller.setPlayerCount(TeamSide.home, 1000);
      expect(readState(c.container).playerCount(TeamSide.home),
          RosterState.maxPlayersPerTeam);
    });

    test('fills a full squad without duplicating identifiers', () {
      final c = makeController();
      c.controller.setPlayerCount(TeamSide.home, RosterState.maxPlayersPerTeam);
      c.controller.setPlayerCount(TeamSide.away, RosterState.maxPlayersPerTeam);

      final state = readState(c.container);
      expect(state.tagCount, RosterState.maxTagCount);
      expect(state.tags.map((t) => t.id).toSet(), hasLength(30));
      expect(state.players.map((p) => p.id).toSet(), hasLength(30));
    });
  });

  group('editing a player', () {
    test('sets the name, number and role independently', () {
      final c = makeController();
      final target = readState(c.container).members.first;

      c.controller.setPlayerName(target.playerId, 'Ada Hansen');
      c.controller.setPlayerNumber(target.playerId, 17);
      c.controller.setPlayerRole(target.playerId, PlayerRole.rightWing);

      final player = readState(c.container).members.first.player;
      expect(player.name, 'Ada Hansen');
      expect(player.number, 17);
      expect(player.role, PlayerRole.rightWing);
    });

    test('clears a shirt number when given none', () {
      final c = makeController();
      final target = readState(c.container).members.first;

      c.controller.setPlayerNumber(target.playerId, null);

      expect(readState(c.container).members.first.player.number, isNull);
    });

    test('editing one player leaves the others untouched', () {
      final c = makeController();
      final others = readState(c.container).members.sublist(1);

      c.controller
          .setPlayerName(readState(c.container).members.first.playerId, 'X');

      expect(readState(c.container).members.sublist(1), others);
    });

    test('moving a player to the other team updates their team name', () {
      final c = makeController();
      c.controller.setTeamName(TeamSide.away, 'Ajax');
      final target = readState(c.container).forSide(TeamSide.home).first;

      c.controller.setPlayerSide(target.playerId, TeamSide.away);

      final moved = readState(c.container)
          .members
          .firstWhere((m) => m.playerId == target.playerId);
      expect(moved.side, TeamSide.away);
      expect(moved.player.team, 'Ajax');
    });
  });

  group('team count', () {
    test('starts at two', () {
      final state = readState(makeController().container);
      expect(state.teamCount, 2);
      expect(state.sides, TeamSide.values);
    });

    test('dropping to one team removes the other team and its players', () {
      final c = makeController();
      c.controller.setTeamCount(1);

      final state = readState(c.container);
      expect(state.teamCount, 1);
      expect(state.sides, [TeamSide.home]);
      expect(state.tagCount, 6);
      expect(state.forSide(TeamSide.away), isEmpty);
    });

    test('reports how many players dropping a team would discard', () {
      final c = makeController();
      expect(c.controller.playersLostByRemovingTeam(1), 6);
      expect(c.controller.playersLostByRemovingTeam(2), 0);
    });

    test('going back to two restores an empty second team', () {
      // The removed players are gone — only the team comes back — so the
      // caller has to have confirmed the loss.
      final c = makeController();
      c.controller.setTeamCount(1);
      c.controller.setTeamCount(2);

      final state = readState(c.container);
      expect(state.teamCount, 2);
      expect(state.playerCount(TeamSide.away), 0);
      expect(state.teamName(TeamSide.away), 'Away');
    });

    test('keeps the remaining team’s name and colour across the change', () {
      final c = makeController();
      c.controller.setTeamName(TeamSide.home, 'Ajax');
      c.controller.setTeamColor(TeamSide.home, Team.colorPalette[4]);

      c.controller.setTeamCount(1);

      final state = readState(c.container);
      expect(state.teamName(TeamSide.home), 'Ajax');
      expect(state.teamColorValue(TeamSide.home), Team.colorPalette[4]);
    });

    test('is clamped to one or two', () {
      final c = makeController();

      c.controller.setTeamCount(0);
      expect(readState(c.container).teamCount, 1);

      c.controller.setTeamCount(9);
      expect(readState(c.container).teamCount, 2);
    });

    test('a player cannot be moved to a team that does not exist', () {
      final c = makeController();
      c.controller.setTeamCount(1);
      final target = readState(c.container).members.first;

      c.controller.setPlayerSide(target.playerId, TeamSide.away);

      expect(readState(c.container).members.first.side, TeamSide.home);
    });
  });

  group('team colours', () {
    test('default to distinct palette entries', () {
      final state = readState(makeController().container);

      expect(state.teamColorValue(TeamSide.home), Team.colorPalette[0]);
      expect(state.teamColorValue(TeamSide.away), Team.colorPalette[1]);
    });

    test('can be changed', () {
      final c = makeController();
      c.controller.setTeamColor(TeamSide.home, Team.colorPalette[5]);

      expect(readState(c.container).teamColorValue(TeamSide.home),
          Team.colorPalette[5]);
    });

    test('never collide: the other team takes the colour just released', () {
      // Two sides sharing a colour would make the live view unreadable.
      final c = makeController();
      final wasHome = readState(c.container).teamColorValue(TeamSide.home);

      c.controller.setTeamColor(TeamSide.away, wasHome);

      final state = readState(c.container);
      expect(state.teamColorValue(TeamSide.away), wasHome);
      expect(state.teamColorValue(TeamSide.home),
          isNot(state.teamColorValue(TeamSide.away)));
    });

    test('choosing a free colour leaves the other team alone', () {
      final c = makeController();
      final wasAway = readState(c.container).teamColorValue(TeamSide.away);

      c.controller.setTeamColor(TeamSide.home, Team.colorPalette[6]);

      expect(readState(c.container).teamColorValue(TeamSide.away), wasAway);
    });
  });

  group('optional roles', () {
    test('a role can be cleared', () {
      final c = makeController();
      final target = readState(c.container).members.first;

      c.controller.setPlayerRole(target.playerId, null);

      expect(readState(c.container).members.first.role, isNull);
    });

    test('players past the standard line-up get no role', () {
      // Seven roles exist; a fifteen-strong squad leaves the rest roleless
      // rather than inventing duplicates.
      final c = makeController();
      c.controller.setPlayerCount(TeamSide.home, RosterState.maxPlayersPerTeam);

      final roleless =
          readState(c.container).forSide(TeamSide.home).where((m) => m.role == null);
      expect(roleless, hasLength(RosterState.maxPlayersPerTeam - PlayerRole.values.length));
    });

    test('a roleless player still has a usable name and tag', () {
      final c = makeController();
      c.controller.setPlayerCount(TeamSide.home, 10);

      final last = readState(c.container).forSide(TeamSide.home).last;
      expect(last.role, isNull);
      expect(last.player.name, isNotEmpty);
      expect(last.tag.hardwareId, isNotEmpty);
    });
  });

  group('team names', () {
    test('rename every player already on that side', () {
      final c = makeController();

      c.controller.setTeamName(TeamSide.home, 'Ajax');

      final state = readState(c.container);
      expect(state.teamName(TeamSide.home), 'Ajax');
      expect(state.forSide(TeamSide.home).every((m) => m.player.team == 'Ajax'),
          isTrue);
      expect(state.forSide(TeamSide.away).every((m) => m.player.team == 'Away'),
          isTrue);
    });

    test('fall back to the default rather than storing a blank name', () {
      final c = makeController();

      c.controller.setTeamName(TeamSide.home, '   ');

      expect(readState(c.container).teamName(TeamSide.home), 'Home');
    });

    test('are trimmed', () {
      final c = makeController();

      c.controller.setTeamName(TeamSide.away, '  Ajax  ');

      expect(readState(c.container).teamName(TeamSide.away), 'Ajax');
    });
  });

  test('reset restores the default roster', () {
    final c = makeController();
    c.controller.setPlayerCount(TeamSide.home, 3);
    c.controller.setTeamCount(1);
    c.controller.setTeamName(TeamSide.home, 'Ajax');

    c.controller.resetRoster();

    final state = readState(c.container);
    expect(state.tagCount, 12);
    expect(state.teamName(TeamSide.home), 'Home');
  });
}
