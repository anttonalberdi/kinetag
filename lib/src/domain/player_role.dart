/// A player's position in the team's formation.
///
/// Lives in the domain rather than in the simulator because the role is
/// something a coach assigns in setup, is stored with the session, and is
/// meant to drive per-role analytics later. The simulator's *movement
/// envelope* for each role is a separate, simulator-only concern — see
/// `RoleMovement` — so that adding a real roster never drags simulation
/// parameters into stored data.
///
/// The seven values are the standard handball line-up. Other sports will add
/// their own roles; nothing outside a role picker enumerates them exhaustively.
enum PlayerRole {
  goalkeeper('Goalkeeper', 'GK', 1),
  leftWing('Left Wing', 'LW', 2),
  leftBack('Left Back', 'LB', 3),
  centreBack('Centre Back', 'CB', 4),
  rightBack('Right Back', 'RB', 5),
  rightWing('Right Wing', 'RW', 6),
  pivot('Pivot', 'PV', 7);

  const PlayerRole(this.displayName, this.shortName, this.defaultShirtNumber);

  final String displayName;

  /// Two-letter abbreviation, for tight layouts.
  final String shortName;

  /// Shirt number suggested when a player is first given this role. Only a
  /// suggestion: numbers are editable and are not required to be unique.
  final int defaultShirtNumber;

  /// The six-a-side line-up Kinetag defaults to.
  ///
  /// Handball fields seven, but the prototype's default roster is two teams of
  /// six — the count the simulator and its tests were built around. A seventh
  /// player is one tap away in setup, which is exactly why the roster is
  /// user-defined now.
  static const List<PlayerRole> defaultLineup = [
    goalkeeper,
    leftWing,
    leftBack,
    centreBack,
    rightBack,
    pivot,
  ];
}
