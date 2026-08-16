import 'package:meta/meta.dart';

import '../../domain/domain.dart';

/// The movement envelope the simulator gives a [PlayerRole].
///
/// Kept out of [PlayerRole] itself so the domain enum stays free of
/// simulation parameters: a role is something a coach assigns and a session
/// stores, whereas `rangeX` and `advanceFactor` mean nothing once real tags
/// are reporting positions.
///
/// ## Coordinates
///
/// [homeX] / [homeY] are fractions of court width / height in a *team-local*
/// frame where the team defends `x = 0` and attacks `+x`. Fractions rather
/// than metres so the same roster works on a court of any size; the away team
/// is obtained by rotating the local frame 180° (see
/// `MatchSimulation.anchorFor`).
///
/// ## Why role-shaped movement at all
///
/// Generic random walks would be cheaper, but role-shaped movement costs
/// almost nothing extra and is what makes team metrics — centroid, width,
/// compactness — mean something: a formation that holds its shape and swings
/// between ends produces recognisable numbers, whereas a dozen independent
/// wanderers produce a constant blur.
@immutable
class RoleMovement {
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

  const RoleMovement({
    required this.homeX,
    required this.homeY,
    required this.rangeX,
    required this.rangeY,
    required this.maxSpeedMps,
    required this.advanceFactor,
  });

  /// Envelope for the [index]-th player on a team with no role assigned.
  ///
  /// Roles are optional — players move between positions during a match — so
  /// a roster may be entirely roleless. Giving every such player the same
  /// envelope would pile them onto one spot; instead they borrow the tuned
  /// envelopes in turn, which keeps a formation plausible and each trajectory
  /// distinct. It is a stand-in for simulation only, never a claim that the
  /// player occupies that position.
  static RoleMovement unassignedAt(int index) {
    final roles = PlayerRole.values;
    return byRole[roles[index % roles.length]]!;
  }

  static const Map<PlayerRole, RoleMovement> byRole = {
    // Goalkeepers barely follow play up the court; they hold their goal.
    PlayerRole.goalkeeper: RoleMovement(
      homeX: 0.05,
      homeY: 0.50,
      rangeX: 0.035,
      rangeY: 0.110,
      maxSpeedMps: 3.5,
      advanceFactor: 0.12,
    ),
    PlayerRole.leftWing: RoleMovement(
      homeX: 0.45,
      homeY: 0.12,
      rangeX: 0.085,
      rangeY: 0.055,
      maxSpeedMps: 7.5,
      advanceFactor: 1.00,
    ),
    PlayerRole.leftBack: RoleMovement(
      homeX: 0.375,
      homeY: 0.28,
      rangeX: 0.070,
      rangeY: 0.075,
      maxSpeedMps: 6.5,
      advanceFactor: 0.92,
    ),
    PlayerRole.centreBack: RoleMovement(
      homeX: 0.325,
      homeY: 0.50,
      rangeX: 0.065,
      rangeY: 0.090,
      maxSpeedMps: 6.0,
      advanceFactor: 0.85,
    ),
    PlayerRole.rightBack: RoleMovement(
      homeX: 0.375,
      homeY: 0.72,
      rangeX: 0.070,
      rangeY: 0.075,
      maxSpeedMps: 6.5,
      advanceFactor: 0.92,
    ),
    // Mirror of the left wing about the court's long axis.
    PlayerRole.rightWing: RoleMovement(
      homeX: 0.45,
      homeY: 0.88,
      rangeX: 0.085,
      rangeY: 0.055,
      maxSpeedMps: 7.5,
      advanceFactor: 1.00,
    ),
    PlayerRole.pivot: RoleMovement(
      homeX: 0.520,
      homeY: 0.50,
      rangeX: 0.055,
      rangeY: 0.140,
      maxSpeedMps: 5.5,
      advanceFactor: 1.00,
    ),
  };

  /// The envelope for a participant who is not fielded.
  ///
  /// A substitute stands at the bench, and the bench is *outside* the court,
  /// so [homeX] / [homeY] — fractions of the court — cannot express where that
  /// is. They are zero here and go unread: a benched participant's anchor is
  /// its seat number resolved to metres by `MatchSimulation.benchSeatAt`.
  /// What this envelope still says truthfully is the rest — no wander, no
  /// following play up the court, and walking pace as the ceiling for any
  /// movement to or from the seat.
  static const RoleMovement benched = RoleMovement(
    homeX: 0,
    homeY: 0,
    rangeX: 0,
    rangeY: 0,
    maxSpeedMps: 1.4,
    advanceFactor: 0,
  );

  /// The envelope for [role]; falls back to the first unassigned slot when
  /// there is none.
  static RoleMovement of(PlayerRole? role) =>
      role == null ? unassignedAt(0) : (byRole[role] ?? unassignedAt(0));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoleMovement &&
          other.homeX == homeX &&
          other.homeY == homeY &&
          other.rangeX == rangeX &&
          other.rangeY == rangeY &&
          other.maxSpeedMps == maxSpeedMps &&
          other.advanceFactor == advanceFactor;

  @override
  int get hashCode =>
      Object.hash(homeX, homeY, rangeX, rangeY, maxSpeedMps, advanceFactor);
}
