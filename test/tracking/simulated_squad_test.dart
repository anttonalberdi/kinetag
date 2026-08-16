import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/setup/roster_state.dart';
import 'package:kinetag/src/tracking/simulator/role_movement.dart';
import 'package:kinetag/src/tracking/simulator/simulated_squad.dart';

void main() {
  final squad = SimulatedSquad.handballTeams();

  group('default squad', () {
    test('fields two teams of six', () {
      expect(squad.participants, hasLength(12));
      expect(squad.forSide(TeamSide.home), hasLength(6));
      expect(squad.forSide(TeamSide.away), hasLength(6));
    });

    test('every role of the standard line-up appears once per team', () {
      for (final side in TeamSide.values) {
        final roles = squad.forSide(side).map((p) => p.role).toSet();
        expect(roles, PlayerRole.defaultLineup.toSet());
      }
    });

    test('tag identifiers are unique', () {
      expect(squad.participants.map((p) => p.tagId).toSet(), hasLength(12));
    });

    test('resolves a tag back to its participant', () {
      final target = squad.participants[7];
      expect(squad.participantForTag(target.tagId), same(target));
      expect(squad.participantForTag('not-a-tag'), isNull);
    });

    test('roles are ordered goalkeeper first', () {
      // The live view lists players in role order; a goalkeeper heading each
      // team keeps that list readable.
      expect(PlayerRole.defaultLineup.first, PlayerRole.goalkeeper);
    });
  });

  group('built from a setup roster', () {
    test('simulates exactly the tags the roster declares', () {
      final roster = RosterState.defaults();
      final built = SimulatedSquad.fromRoster(
        players: roster.players,
        tags: roster.tags,
        assignments: roster.assignments,
      );

      expect(built.participants.map((p) => p.tagId).toList(),
          roster.tags.map((t) => t.id).toList());
      expect(built, squad,
          reason: 'the default roster and the stand-alone default squad must '
              'describe the same simulation');
    });

    test('carries each player’s role and side across', () {
      final roster = RosterState.defaults();
      final target = roster.members.last;

      final built = SimulatedSquad.fromRoster(
        players: roster.players,
        tags: roster.tags,
        assignments: roster.assignments,
      );

      final participant = built.participantForTag(target.tagId)!;
      expect(participant.role, target.player.role);
      expect(participant.side, target.player.side);
    });

    test('still simulates a tag nobody is wearing', () {
      // Hardware reports every tag it can hear, registered or not.
      final built = SimulatedSquad.fromRoster(
        players: const [],
        assignments: const [],
        tags: const [Tag(id: 'spare', hardwareId: 'HW-1', name: 'Spare')],
      );

      expect(built.participants, hasLength(1));
      expect(built.participants.single.role, isNull);
      expect(built.participants.single.movement, RoleMovement.unassignedAt(0));
    });
  });

  group('roleless players', () {
    RosterState rolelessRoster(int count) {
      var roster = RosterState.defaults();
      return roster.copyWith(
        members: [
          for (final m in roster.members.take(count))
            m.copyWith(player: m.player.copyWith(clearRole: true)),
        ],
      );
    }

    SimulatedSquad squadFor(RosterState roster) => SimulatedSquad.fromRoster(
          players: roster.players,
          tags: roster.tags,
          assignments: roster.assignments,
        );

    test('are simulated with distinct envelopes rather than one heap', () {
      // Roles are optional, so a whole squad may be roleless. Giving them all
      // the same envelope would pile them onto one spot on court.
      final squad = squadFor(rolelessRoster(6));

      expect(squad.participants.every((p) => p.role == null), isTrue);
      expect(squad.participants.map((p) => p.movement).toSet(), hasLength(6));
    });

    test('count their stand-in envelopes per side', () {
      // The two sides each start from the first envelope, so a roleless
      // 2-team roster produces two spread formations, not one.
      var roster = RosterState.defaults();
      roster = roster.copyWith(
        members: [
          for (final m in roster.members)
            m.copyWith(player: m.player.copyWith(clearRole: true)),
        ],
      );
      final squad = squadFor(roster);

      expect(squad.forSide(TeamSide.home).map((p) => p.movement).toSet(),
          hasLength(6));
      expect(squad.forSide(TeamSide.home).first.movement,
          squad.forSide(TeamSide.away).first.movement);
    });
  });

  group('line-up', () {
    /// A roster of [perSide] players per side: a goalkeeper, then outfield
    /// roles taken in order and repeated once the seven run out.
    RosterState rosterOf(int perSide) {
      var roster = RosterState.defaults();
      final outfield =
          PlayerRole.values.where((r) => r != PlayerRole.goalkeeper).toList();

      final members = <RosterMember>[];
      for (final side in TeamSide.values) {
        final template = roster.members.where((m) => m.side == side).toList();
        for (var i = 0; i < perSide; i++) {
          final source = template[i % template.length];
          members.add(
            source.copyWith(
              player: source.player.copyWith(
                id: '$side-$i',
                role: i == 0
                    ? PlayerRole.goalkeeper
                    : outfield[(i - 1) % outfield.length],
              ),
              tag: source.tag.copyWith(id: 'tag-$side-$i'),
              assignment: source.assignment
                  .copyWith(playerId: '$side-$i', tagId: 'tag-$side-$i'),
            ),
          );
        }
      }

      return roster.copyWith(members: members);
    }

    SimulatedSquad squadFor(RosterState roster, int fieldPlayers) =>
        SimulatedSquad.fromRoster(
          players: roster.players,
          tags: roster.tags,
          assignments: roster.assignments,
          fieldPlayersOnCourt: fieldPlayers,
        );

    test('fields a goalkeeper plus the chosen number of field players', () {
      final roster = rosterOf(9);

      for (var n = SimulatedSquad.minFieldPlayersOnCourt;
          n <= SimulatedSquad.maxFieldPlayersOnCourt;
          n++) {
        final squad = squadFor(roster, n);

        for (final side in TeamSide.values) {
          final fielded = squad.forSide(side).where((p) => p.isOnCourt);
          expect(fielded, hasLength(n + 1),
              reason: '1 + $n is $n field players and one keeper');
          expect(
            fielded.where((p) => p.role == PlayerRole.goalkeeper),
            hasLength(1),
          );
        }
      }
    });

    test('the default line-up fields the default roster whole', () {
      // 1 + 5 is exactly PlayerRole.defaultLineup, so nothing changes for an
      // operator who never opens the setting.
      final squad = SimulatedSquad.fromRoster(
        players: RosterState.defaults().players,
        tags: RosterState.defaults().tags,
        assignments: RosterState.defaults().assignments,
      );

      expect(squad.benched, isEmpty);
      expect(SimulatedSquad.defaultFieldPlayersOnCourt, 5);
    });

    test('everybody beyond the line-up is benched, in roster order', () {
      final roster = rosterOf(9);
      final squad = squadFor(roster, 4);

      for (final side in TeamSide.values) {
        final benched = squad.forSide(side).where((p) => !p.isOnCourt).toList();

        // Nine minus a keeper and four field players.
        expect(benched, hasLength(4));
        expect([for (final p in benched) p.benchSeat], [0, 1, 2, 3]);
        expect(benched.every((p) => p.movement == RoleMovement.benched), isTrue);

        // And the ones who play are the ones the roster listed first.
        final fielded = squad.forSide(side).where((p) => p.isOnCourt);
        expect(
          fielded.map((p) => p.tagId).toList(),
          [for (var i = 0; i < 5; i++) 'tag-$side-$i'],
        );
      }
    });

    test('a side can only field as many players as it holds', () {
      // Asking for 1 + 6 with six players registered is not an error; it just
      // fields all six.
      final squad = squadFor(rosterOf(6), 6);

      expect(squad.benched, isEmpty);
      expect(squad.forSide(TeamSide.home), hasLength(6));
    });

    test('a substitute goalkeeper sits rather than playing out', () {
      var roster = rosterOf(7);
      // Make the second player of each side a second keeper.
      roster = roster.copyWith(
        members: [
          for (final m in roster.members)
            m.tag.id.endsWith('-1')
                ? m.copyWith(
                    player: m.player.copyWith(role: PlayerRole.goalkeeper))
                : m,
        ],
      );

      final squad = squadFor(roster, 5);
      final backup = squad.participantForTag('tag-${TeamSide.home}-1')!;

      expect(backup.isOnCourt, isFalse,
          reason: 'a spare keeper is a substitute, not an outfield player');
      expect(squad.forSide(TeamSide.home).where((p) => p.isOnCourt),
          hasLength(6));
    });

    test('a side with no goalkeeper fields one more outfield player instead',
        () {
      // How many players are on court must not depend on whether anybody got
      // around to assigning roles.
      var roster = rosterOf(9);
      roster = roster.copyWith(
        members: [
          for (final m in roster.members)
            m.copyWith(player: m.player.copyWith(clearRole: true)),
        ],
      );

      final squad = squadFor(roster, 5);

      for (final side in TeamSide.values) {
        expect(squad.forSide(side).where((p) => p.isOnCourt), hasLength(6));
      }
    });

    test('the line-up is part of squad identity', () {
      // Otherwise a substitution would leave the tracking source simulating
      // the previous line-up.
      final roster = rosterOf(9);
      expect(squadFor(roster, 4), isNot(squadFor(roster, 5)));
    });
  });

  group('equality', () {
    // Narrow equality is what stops a rename in setup from rebuilding the
    // tracking source underneath a running recording.
    RosterState renamed() {
      final roster = RosterState.defaults();
      final first = roster.members.first;
      return roster.copyWith(
        members: [
          first.copyWith(player: first.player.copyWith(name: 'Somebody Else')),
          ...roster.members.skip(1),
        ],
      );
    }

    SimulatedSquad squadFor(RosterState roster) => SimulatedSquad.fromRoster(
          players: roster.players,
          tags: roster.tags,
          assignments: roster.assignments,
        );

    test('ignores names, so renaming a player changes nothing', () {
      expect(squadFor(renamed()), squadFor(RosterState.defaults()));
    });

    test('notices a changed role', () {
      final roster = RosterState.defaults();
      final first = roster.members.first;
      final rerolled = roster.copyWith(
        members: [
          first.copyWith(
              player: first.player.copyWith(role: PlayerRole.rightWing)),
          ...roster.members.skip(1),
        ],
      );

      expect(squadFor(rerolled), isNot(squadFor(roster)));
    });

    test('notices a changed tag count', () {
      final roster = RosterState.defaults();
      final shorter =
          roster.copyWith(members: roster.members.sublist(0, 11));

      expect(squadFor(shorter), isNot(squadFor(roster)));
    });
  });
}
