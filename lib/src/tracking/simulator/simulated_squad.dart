import 'package:meta/meta.dart';

import '../../domain/domain.dart';

/// One of the two simulated sides.
enum SimulatedTeam {
  home('Home'),
  away('Away');

  const SimulatedTeam(this.displayName);

  final String displayName;
}

/// A handball role together with the movement envelope that makes each
/// simulated player behave differently from the others.
///
/// ## Coordinates
///
/// [homeX] / [homeY] are fractions of court width / height in a *team-local*
/// frame where the team defends `x = 0` and attacks `+x`. Fractions rather
/// than metres so the same roster works on a court of any size; the away team
/// is obtained by rotating the local frame 180° (see
/// `MatchSimulation.anchorFor`).
///
/// ## Why roles at all
///
/// Generic random walks would be cheaper, but role-shaped movement costs
/// almost nothing extra and is what makes the later team metrics — centroid,
/// width, compactness — mean something: a formation that holds its shape and
/// swings between ends produces recognisable numbers, whereas twelve
/// independent wanderers produce a constant blur.
enum PlayerRole {
  goalkeeper(
    displayName: 'Goalkeeper',
    shirtNumber: 1,
    homeX: 0.05,
    homeY: 0.50,
    rangeX: 0.035,
    rangeY: 0.110,
    maxSpeedMps: 3.5,
    // Goalkeepers barely follow play up the court; they hold their goal.
    advanceFactor: 0.12,
  ),
  leftWing(
    displayName: 'Left Wing',
    shirtNumber: 2,
    homeX: 0.45,
    homeY: 0.12,
    rangeX: 0.085,
    rangeY: 0.055,
    maxSpeedMps: 7.5,
    advanceFactor: 1.00,
  ),
  leftBack(
    displayName: 'Left Back',
    shirtNumber: 3,
    homeX: 0.375,
    homeY: 0.28,
    rangeX: 0.070,
    rangeY: 0.075,
    maxSpeedMps: 6.5,
    advanceFactor: 0.92,
  ),
  centreBack(
    displayName: 'Centre Back',
    shirtNumber: 4,
    homeX: 0.325,
    homeY: 0.50,
    rangeX: 0.065,
    rangeY: 0.090,
    maxSpeedMps: 6.0,
    advanceFactor: 0.85,
  ),
  rightBack(
    displayName: 'Right Back',
    shirtNumber: 5,
    homeX: 0.375,
    homeY: 0.72,
    rangeX: 0.070,
    rangeY: 0.075,
    maxSpeedMps: 6.5,
    advanceFactor: 0.92,
  ),
  pivot(
    displayName: 'Pivot',
    shirtNumber: 6,
    homeX: 0.520,
    homeY: 0.50,
    rangeX: 0.055,
    rangeY: 0.140,
    maxSpeedMps: 5.5,
    advanceFactor: 1.00,
  );

  const PlayerRole({
    required this.displayName,
    required this.shirtNumber,
    required this.homeX,
    required this.homeY,
    required this.rangeX,
    required this.rangeY,
    required this.maxSpeedMps,
    required this.advanceFactor,
  });

  final String displayName;

  /// Shirt number within the team. Unique per team, shared across teams, as
  /// in a real match.
  final int shirtNumber;

  /// Neutral-phase anchor, as a fraction of court width / height.
  final double homeX;
  final double homeY;

  /// Half-extent of the region this player wanders in, as a fraction of court
  /// width / height.
  final double rangeX;
  final double rangeY;

  /// Sprint ceiling in metres per second.
  final double maxSpeedMps;

  /// How much of the attack/defence swing this role follows, 0..1.
  final double advanceFactor;
}

/// One simulated player, complete with the hardware records a real session
/// would carry.
///
/// Bundling [player], [tag] and [assignment] here means the simulator can
/// hand a recording the same setup snapshot a real capture would produce, so
/// `Session` needs no simulator-specific branch.
@immutable
class SimulatedParticipant {
  final SimulatedTeam team;
  final PlayerRole role;
  final Player player;
  final Tag tag;
  final TagAssignment assignment;

  const SimulatedParticipant({
    required this.team,
    required this.role,
    required this.player,
    required this.tag,
    required this.assignment,
  });

  String get tagId => tag.id;

  @override
  String toString() =>
      'SimulatedParticipant(${team.displayName} ${role.displayName})';
}

/// A full simulated roster: two teams of six.
///
/// Adding a value to [PlayerRole] adds one player per team, so growing to a
/// full seven-a-side handball squad (or shrinking for small-sided drills) is
/// a one-line change rather than a rewrite.
@immutable
class SimulatedSquad {
  final List<SimulatedParticipant> participants;

  const SimulatedSquad(this.participants);

  /// The default roster: [SimulatedTeam.home] and [SimulatedTeam.away], each
  /// fielding every [PlayerRole].
  factory SimulatedSquad.handballTeams() {
    final participants = <SimulatedParticipant>[];
    var hardwareIndex = 0;

    for (final team in SimulatedTeam.values) {
      for (final role in PlayerRole.values) {
        hardwareIndex++;
        final slug = '${team.name}-${role.name}';
        final playerId = 'sim-player-$slug';
        final tagId = 'sim-tag-$slug';

        participants.add(
          SimulatedParticipant(
            team: team,
            role: role,
            player: Player(
              id: playerId,
              name: '${team.displayName} ${role.displayName}',
              number: role.shirtNumber,
              team: team.displayName,
              // Carried in metadata so a recorded session still knows the
              // role after the simulator is gone.
              metadata: {'role': role.name, 'simulated': true},
            ),
            tag: Tag(
              id: tagId,
              hardwareId: 'SIM-${hardwareIndex.toString().padLeft(4, '0')}',
              name: '${team.displayName} #${role.shirtNumber}',
              connectionState: DeviceConnectionState.connected,
            ),
            assignment: TagAssignment(
              id: 'sim-assignment-$slug',
              playerId: playerId,
              tagId: tagId,
              // The prototype wears one tag; the target hardware is
              // shoe-mounted, so record which shoe from the start.
              location: TagMountLocation.rightShoe,
            ),
          ),
        );
      }
    }

    return SimulatedSquad(List.unmodifiable(participants));
  }

  List<Player> get players => [for (final p in participants) p.player];
  List<Tag> get tags => [for (final p in participants) p.tag];
  List<TagAssignment> get assignments =>
      [for (final p in participants) p.assignment];

  Iterable<SimulatedParticipant> forTeam(SimulatedTeam team) =>
      participants.where((p) => p.team == team);

  SimulatedParticipant? participantForTag(String tagId) {
    for (final p in participants) {
      if (p.tag.id == tagId) return p;
    }
    return null;
  }

  @override
  String toString() => 'SimulatedSquad(${participants.length} players)';
}
