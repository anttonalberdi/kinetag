import 'package:meta/meta.dart';

import '../../domain/domain.dart';
import 'role_movement.dart';

/// A tag the simulation must place, before it is known whether it plays.
///
/// A record rather than a class because it never leaves this file: it exists
/// only so the two squad factories can share one selection rule instead of
/// each growing its own copy.
typedef _Candidate = ({TeamSide side, PlayerRole? role, String tagId});

/// One simulated player: a tag to emit positions for, and the role and side
/// that shape how it moves.
///
/// ## Equality is deliberately narrow
///
/// Two participants are equal when they would produce the *same simulated
/// movement* — same tag, same role, same side, same seat. Names, shirt numbers
/// and battery levels are excluded on purpose. The squad is rebuilt from the
/// setup roster on every edit, and `Provider` only notifies its dependants when
/// the new value differs; narrow equality is therefore what stops renaming a
/// player from tearing down and restarting the tracking source underneath a
/// running recording.
@immutable
class SimulatedParticipant {
  final TeamSide side;
  final PlayerRole? role;

  /// The tag positions are emitted for.
  final String tagId;

  /// Seat on this side's bench, or null when the participant is fielded.
  ///
  /// Part of the movement identity rather than a display detail: a
  /// substitution changes where a tag's positions come from without changing
  /// any tag, and the simulation has to be rebuilt when it does.
  final int? benchSeat;

  /// How this participant moves. Follows [role] when there is one, is
  /// [RoleMovement.benched] for a substitute, and is otherwise a stand-in
  /// envelope chosen so roleless players still spread out — see
  /// [RoleMovement.unassignedAt].
  final RoleMovement movement;

  SimulatedParticipant({
    required this.side,
    required this.role,
    required this.tagId,
    this.benchSeat,
    RoleMovement? movement,
  }) : movement = movement ??
            (benchSeat == null ? RoleMovement.of(role) : RoleMovement.benched);

  /// Whether this participant is fielded rather than sitting out.
  bool get isOnCourt => benchSeat == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimulatedParticipant &&
          other.side == side &&
          other.role == role &&
          other.tagId == tagId &&
          other.benchSeat == benchSeat &&
          other.movement == movement;

  @override
  int get hashCode => Object.hash(side, role, tagId, benchSeat, movement);

  @override
  String toString() =>
      'SimulatedParticipant(${side.displayName} '
      '${role?.displayName ?? 'unassigned'}, $tagId'
      '${benchSeat == null ? '' : ', bench $benchSeat'})';
}

/// The tags a simulated match produces data for.
///
/// Holds no [Player] or [Tag] records: the roster entered in setup is the
/// single source of truth for who wears what, and the simulator only needs to
/// know which tag ids to emit and how each should move. Keeping copies here
/// would be a second source of truth that a rename could put out of step.
@immutable
class SimulatedSquad {
  final List<SimulatedParticipant> participants;

  const SimulatedSquad(this.participants);

  /// Field players a side puts on court, excluding its goalkeeper.
  ///
  /// Handball is played seven-a-side, but the small-sided games clubs actually
  /// train with run 1+4 and 1+5 as well, so the line-up is a knob rather than
  /// a constant. Whoever the roster holds beyond the fielded line-up sits on
  /// the bench — nobody is dropped from the simulation, because a tag that is
  /// switched on keeps reporting whether or not its wearer is playing.
  static const int minFieldPlayersOnCourt = 4;
  static const int maxFieldPlayersOnCourt = 6;

  /// Matches [PlayerRole.defaultLineup], so the default roster fields
  /// everybody it declares and the bench starts empty.
  static const int defaultFieldPlayersOnCourt = 5;

  /// The stand-alone default: two teams of [PlayerRole.defaultLineup], used
  /// when nothing has overridden the squad from setup.
  ///
  /// At the default 1 + 5 that fields all six; a shorter line-up benches the
  /// roles the lineup lists last, exactly as it would for a real roster.
  factory SimulatedSquad.handballTeams({
    int fieldPlayersOnCourt = defaultFieldPlayersOnCourt,
  }) {
    final candidates = <_Candidate>[];
    var index = 0;

    for (final side in TeamSide.values) {
      for (final role in PlayerRole.defaultLineup) {
        index++;
        candidates.add((
          side: side,
          role: role,
          tagId: 'tag-${index.toString().padLeft(2, '0')}',
        ));
      }
    }

    return SimulatedSquad(_field(candidates, fieldPlayersOnCourt));
  }

  /// Builds a squad from a roster of players, tags and assignments.
  ///
  /// This is what connects setup to the simulator: whatever tags the operator
  /// defines are the tags data arrives for. A tag with no assigned player is
  /// still simulated — hardware reports every tag it can hear, whether or not
  /// anybody has registered its wearer, and the live view already draws such
  /// tags as unassigned.
  ///
  /// [fieldPlayersOnCourt] decides how many of them actually play; see
  /// [_field] for who is picked.
  factory SimulatedSquad.fromRoster({
    required List<Player> players,
    required List<Tag> tags,
    required List<TagAssignment> assignments,
    int fieldPlayersOnCourt = defaultFieldPlayersOnCourt,
  }) {
    final playerById = {for (final p in players) p.id: p};

    Player? wearerOf(String tagId) {
      for (final assignment in assignments) {
        if (assignment.tagId == tagId) return playerById[assignment.playerId];
      }
      return null;
    }

    final candidates = <_Candidate>[];
    for (final tag in tags) {
      final player = wearerOf(tag.id);
      candidates.add((
        // An unassigned tag has to attack some end; home is as good a choice
        // as any and keeps the participant's motion defined.
        side: player?.side ?? TeamSide.home,
        role: player?.role,
        tagId: tag.id,
      ));
    }

    return SimulatedSquad(_field(candidates, fieldPlayersOnCourt));
  }

  /// Splits [candidates] into a fielded line-up and a bench, per side.
  ///
  /// The rule is roster order, because roster order is the only ranking the
  /// operator has actually expressed: the first goalkeeper of a side keeps
  /// goal, the first [fieldPlayersOnCourt] non-goalkeepers play out, and
  /// everybody after that takes the next free seat on that side's bench. A
  /// second goalkeeper is a substitute rather than an outfield player — that
  /// is what makes the line-up "1 + n" rather than "n + 1 of whoever comes
  /// first".
  ///
  /// A side that declares no goalkeeper at all fields one more outfield player
  /// instead of leaving the slot empty. Roles are optional in setup, and how
  /// many players a side has on court should not quietly depend on whether
  /// anybody got around to assigning them.
  ///
  /// A side can only field what its roster holds, so asking for 1 + 6 with six
  /// players registered simply fields all six and benches nobody.
  static List<SimulatedParticipant> _field(
    List<_Candidate> candidates,
    int fieldPlayersOnCourt,
  ) {
    assert(fieldPlayersOnCourt >= 0, 'a line-up cannot be negative');

    final keeperSides = {
      for (final c in candidates)
        if (c.role == PlayerRole.goalkeeper) c.side,
    };

    final hasKeeper = <TeamSide, bool>{};
    final outfieldCount = <TeamSide, int>{};
    // Roleless players are handed stand-in envelopes in turn, counted per
    // side, so that a roster with no roles at all still produces two spread
    // formations rather than two heaps. Only fielded players consume one.
    final rolelessSeats = <TeamSide, int>{};
    final benchSeats = <TeamSide, int>{};
    final participants = <SimulatedParticipant>[];

    for (final candidate in candidates) {
      final side = candidate.side;
      final role = candidate.role;

      final bool fielded;
      if (role == PlayerRole.goalkeeper) {
        fielded = !(hasKeeper[side] ?? false);
        if (fielded) hasKeeper[side] = true;
      } else {
        final budget = keeperSides.contains(side)
            ? fieldPlayersOnCourt
            : fieldPlayersOnCourt + 1;
        final played = outfieldCount[side] ?? 0;
        fielded = played < budget;
        if (fielded) outfieldCount[side] = played + 1;
      }

      if (!fielded) {
        final seat = benchSeats[side] ?? 0;
        benchSeats[side] = seat + 1;
        participants.add(
          SimulatedParticipant(
            side: side,
            role: role,
            tagId: candidate.tagId,
            benchSeat: seat,
          ),
        );
        continue;
      }

      RoleMovement movement;
      if (role != null) {
        movement = RoleMovement.of(role);
      } else {
        final seat = rolelessSeats[side] ?? 0;
        rolelessSeats[side] = seat + 1;
        movement = RoleMovement.unassignedAt(seat);
      }

      participants.add(
        SimulatedParticipant(
          side: side,
          role: role,
          tagId: candidate.tagId,
          movement: movement,
        ),
      );
    }

    return List.unmodifiable(participants);
  }

  int get length => participants.length;
  bool get isEmpty => participants.isEmpty;

  Iterable<SimulatedParticipant> forSide(TeamSide side) =>
      participants.where((p) => p.side == side);

  /// The fielded participants, in roster order.
  Iterable<SimulatedParticipant> get onCourt =>
      participants.where((p) => p.isOnCourt);

  /// The substitutes, in roster order.
  Iterable<SimulatedParticipant> get benched =>
      participants.where((p) => !p.isOnCourt);

  SimulatedParticipant? participantForTag(String tagId) {
    for (final p in participants) {
      if (p.tagId == tagId) return p;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SimulatedSquad) return false;
    if (other.participants.length != participants.length) return false;
    for (var i = 0; i < participants.length; i++) {
      if (other.participants[i] != participants[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(participants);

  @override
  String toString() => 'SimulatedSquad(${participants.length} tags)';
}
