import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../domain/domain.dart';

/// A tag, the player wearing it, and the assignment binding the two.
///
/// The three domain objects are kept whole rather than flattened into one
/// editable row type, because that is the shape a `Session` snapshots and the
/// shape real hardware will arrive in. Editing a roster row therefore produces
/// exactly the records a recording stores, with no translation step that could
/// drift.
@immutable
class RosterMember {
  final Player player;
  final Tag tag;
  final TagAssignment assignment;

  const RosterMember({
    required this.player,
    required this.tag,
    required this.assignment,
  });

  String get playerId => player.id;
  String get tagId => tag.id;
  TeamSide get side => player.side ?? TeamSide.home;
  PlayerRole? get role => player.role;

  RosterMember copyWith({Player? player, Tag? tag, TagAssignment? assignment}) =>
      RosterMember(
        player: player ?? this.player,
        tag: tag ?? this.tag,
        assignment: assignment ?? this.assignment,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosterMember &&
          other.player == player &&
          other.tag == tag &&
          other.assignment == assignment;

  @override
  int get hashCode => Object.hash(player, tag, assignment);
}

/// The teams and players configured in setup.
///
/// Teams come first and players belong to one: a session is one or two sides,
/// and every player-facing decision — colour on court, which goal they attack,
/// how team metrics are grouped — follows from the team rather than from the
/// player.
@immutable
class RosterState {
  /// One or two teams, in [TeamSide] order.
  final List<Team> teams;

  final List<RosterMember> members;

  /// Monotonic counter behind generated ids and hardware labels.
  ///
  /// Never reused, so removing a player and adding another cannot produce two
  /// records that a stored session would confuse for one another.
  final int nextIndex;

  const RosterState({
    required this.teams,
    required this.members,
    required this.nextIndex,
  });

  /// A session is one team (a training drill) or two (a match).
  static const int minTeamCount = 1;
  static const int maxTeamCount = 2;

  /// Squad ceiling per team: a fielded seven plus a bench.
  static const int maxPlayersPerTeam = 15;

  /// Players a full two-team session can carry, and so the most tags the
  /// roster will ever declare.
  static const int maxTagCount = maxPlayersPerTeam * maxTeamCount;

  /// The default roster: two teams fielding [PlayerRole.defaultLineup].
  factory RosterState.defaults() {
    var index = 1;
    final members = <RosterMember>[];

    for (final side in TeamSide.values) {
      for (final role in PlayerRole.defaultLineup) {
        members.add(
          _member(
            index: index++,
            side: side,
            teamName: side.displayName,
            role: role,
            name: '${side.displayName} ${role.displayName}',
            number: role.defaultShirtNumber,
          ),
        );
      }
    }

    return RosterState(
      teams: List.unmodifiable(
          [for (final side in TeamSide.values) Team.defaults(side)]),
      members: List.unmodifiable(members),
      nextIndex: index,
    );
  }

  int get teamCount => teams.length;
  int get tagCount => members.length;

  /// The sides that currently have a team, in order.
  List<TeamSide> get sides => [for (final team in teams) team.side];

  List<Player> get players => [for (final m in members) m.player];
  List<Tag> get tags => [for (final m in members) m.tag];
  List<TagAssignment> get assignments => [for (final m in members) m.assignment];

  Team? teamFor(TeamSide side) {
    for (final team in teams) {
      if (team.side == side) return team;
    }
    return null;
  }

  String teamName(TeamSide side) => teamFor(side)?.name ?? side.displayName;

  int teamColorValue(TeamSide side) =>
      teamFor(side)?.colorValue ?? Team.defaultColorFor(side);

  List<RosterMember> forSide(TeamSide side) =>
      [for (final m in members) if (m.side == side) m];

  int playerCount(TeamSide side) => forSide(side).length;

  bool canAddTo(TeamSide side) =>
      teamFor(side) != null && playerCount(side) < maxPlayersPerTeam;

  /// Roles already taken on [side], for suggesting the next one.
  Set<PlayerRole> rolesTaken(TeamSide side) =>
      {for (final m in forSide(side)) if (m.role != null) m.role!};

  RosterState copyWith({
    List<Team>? teams,
    List<RosterMember>? members,
    int? nextIndex,
  }) =>
      RosterState(
        teams: teams ?? this.teams,
        members: members ?? this.members,
        nextIndex: nextIndex ?? this.nextIndex,
      );

  /// Builds one member with consistent ids across its three records.
  static RosterMember _member({
    required int index,
    required TeamSide side,
    required String teamName,
    required PlayerRole? role,
    required String name,
    required int? number,
  }) {
    final suffix = index.toString().padLeft(2, '0');
    final playerId = 'player-$suffix';
    final tagId = 'tag-$suffix';

    return RosterMember(
      player: Player(
        id: playerId,
        name: name,
        number: number,
        team: teamName,
        side: side,
        role: role,
      ),
      tag: Tag(
        id: tagId,
        // A placeholder until a real tag is paired: the hardware id is what
        // the hub will report, so it stays a distinct field rather than being
        // folded into the application id.
        hardwareId: 'TAG-${index.toString().padLeft(4, '0')}',
        name: 'Tag $suffix',
        connectionState: DeviceConnectionState.unknown,
      ),
      assignment: TagAssignment(
        id: 'assignment-$suffix',
        playerId: playerId,
        tagId: tagId,
        // The prototype wears one tag; the target hardware is shoe-mounted,
        // so record which shoe from the start.
        location: TagMountLocation.rightShoe,
      ),
    );
  }
}

/// Owns the teams and players entered in setup.
///
/// Free of widget imports for the same reason as `SetupController`: the roster
/// rules — squad limits, role suggestions, keeping a player's team name in
/// step with their side — are testable without pumping a widget tree.
class RosterController extends Notifier<RosterState> {
  @override
  RosterState build() => RosterState.defaults();

  /// Sets how many teams the session has, 1 or 2.
  ///
  /// Dropping to one team **removes the second team's players**; there is
  /// nowhere else for them to go, and silently folding them into the remaining
  /// side would put opponents on the same team. Callers that can lose data
  /// this way should confirm first — [playersLostByRemovingTeam] says how many.
  void setTeamCount(int count) {
    final target =
        count.clamp(RosterState.minTeamCount, RosterState.maxTeamCount);
    if (target == state.teamCount) return;

    final sides = TeamSide.values.take(target).toSet();

    state = state.copyWith(
      teams: [
        for (final side in TeamSide.values)
          if (sides.contains(side))
            state.teamFor(side) ?? Team.defaults(side),
      ],
      members: [
        for (final m in state.members)
          if (sides.contains(m.side)) m,
      ],
    );
  }

  /// How many players would be discarded by dropping to [count] teams.
  int playersLostByRemovingTeam(int count) {
    final target =
        count.clamp(RosterState.minTeamCount, RosterState.maxTeamCount);
    final kept = TeamSide.values.take(target).toSet();
    return state.members.where((m) => !kept.contains(m.side)).length;
  }

  /// Renames a team, updating every player already on that side.
  ///
  /// Blank names fall back to the side's default rather than being stored, so
  /// the on-court legend can never end up labelled with an empty string.
  void setTeamName(TeamSide side, String name) {
    final trimmed = name.trim();
    final resolved = trimmed.isEmpty ? side.displayName : trimmed;

    _updateTeam(side, (team) => team.copyWith(name: resolved));
    state = state.copyWith(
      members: [
        for (final m in state.members)
          if (m.side == side)
            m.copyWith(player: m.player.copyWith(team: resolved))
          else
            m,
      ],
    );
  }

  /// Sets the colour a team's players are drawn in.
  ///
  /// Two teams sharing a colour would make the live view unreadable, so the
  /// other side gives way: it takes the colour this one just released, which
  /// keeps both distinct without silently rejecting the coach's choice.
  void setTeamColor(TeamSide side, int colorValue) {
    final current = state.teamFor(side);
    if (current == null || current.colorValue == colorValue) return;

    final previous = current.colorValue;
    state = state.copyWith(
      teams: [
        for (final team in state.teams)
          if (team.side == side)
            team.copyWith(colorValue: colorValue)
          else if (team.colorValue == colorValue)
            team.copyWith(colorValue: previous)
          else
            team,
      ],
    );
  }

  /// Adds one player to [side], or to the smaller team when none is given.
  ///
  /// Returns the new member, or null when that team is already full or does
  /// not exist.
  RosterMember? addPlayer({TeamSide? side}) {
    final target = side ?? _smallerSide();
    if (!state.canAddTo(target)) return null;

    final index = state.nextIndex;
    final role = _suggestRole(target);
    final teamName = state.teamName(target);

    final member = RosterState._member(
      index: index,
      side: target,
      teamName: teamName,
      role: role,
      name: role == null
          ? '$teamName player ${state.playerCount(target) + 1}'
          : '$teamName ${role.displayName}',
      number: role?.defaultShirtNumber,
    );

    state = state.copyWith(
      members: [...state.members, member],
      nextIndex: index + 1,
    );
    return member;
  }

  /// Removes a player and the tag assignment that went with it.
  void removePlayer(String playerId) => state = state.copyWith(
        members: [
          for (final m in state.members)
            if (m.playerId != playerId) m,
        ],
      );

  /// Grows or shrinks one team to [count] players.
  ///
  /// Shrinking removes the most recently added, which is what an operator who
  /// over-shot the count expects to lose.
  void setPlayerCount(TeamSide side, int count) {
    if (state.teamFor(side) == null) return;
    final target = count.clamp(0, RosterState.maxPlayersPerTeam);

    while (state.playerCount(side) < target) {
      if (addPlayer(side: side) == null) break;
    }

    while (state.playerCount(side) > target) {
      removePlayer(state.forSide(side).last.playerId);
    }
  }

  void setPlayerName(String playerId, String name) => _updatePlayer(
        playerId,
        (p) => p.copyWith(name: name),
      );

  /// Sets a shirt number, or clears it when [number] is null.
  void setPlayerNumber(String playerId, int? number) => _updatePlayer(
        playerId,
        (p) => number == null
            ? p.copyWith(clearNumber: true)
            : p.copyWith(number: number),
      );

  /// Sets a player's role, or clears it when [role] is null.
  ///
  /// Roles are optional throughout: players move between positions during a
  /// match, and a squad list is useful long before anyone has decided who
  /// starts where.
  void setPlayerRole(String playerId, PlayerRole? role) => _updatePlayer(
        playerId,
        (p) => role == null ? p.copyWith(clearRole: true) : p.copyWith(role: role),
      );

  /// Moves a player to the other team, keeping their team *name* in step.
  ///
  /// Does nothing when that team does not exist or is full.
  void setPlayerSide(String playerId, TeamSide side) {
    if (!state.canAddTo(side)) return;
    _updatePlayer(
      playerId,
      (p) => p.copyWith(side: side, team: state.teamName(side)),
    );
  }

  void resetRoster() => state = RosterState.defaults();

  /// The side to add to next: the one with fewer players, home on a tie.
  TeamSide _smallerSide() {
    final sides = state.sides;
    if (sides.isEmpty) return TeamSide.home;

    var best = sides.first;
    for (final side in sides.skip(1)) {
      if (state.playerCount(side) < state.playerCount(best)) best = side;
    }
    return best;
  }

  /// First role in the standard line-up not yet filled on [side].
  ///
  /// Null once every role is taken, which is the normal case past a fielded
  /// squad: the rest of the bench simply has no role until someone assigns
  /// one.
  PlayerRole? _suggestRole(TeamSide side) {
    final taken = state.rolesTaken(side);
    for (final role in PlayerRole.defaultLineup) {
      if (!taken.contains(role)) return role;
    }
    for (final role in PlayerRole.values) {
      if (!taken.contains(role)) return role;
    }
    return null;
  }

  void _updateTeam(TeamSide side, Team Function(Team) update) {
    state = state.copyWith(
      teams: [
        for (final team in state.teams)
          if (team.side == side) update(team) else team,
      ],
    );
  }

  void _updatePlayer(String playerId, Player Function(Player) update) {
    state = state.copyWith(
      members: [
        for (final m in state.members)
          if (m.playerId == playerId) m.copyWith(player: update(m.player)) else m,
      ],
    );
  }
}

final rosterControllerProvider =
    NotifierProvider<RosterController, RosterState>(RosterController.new);
