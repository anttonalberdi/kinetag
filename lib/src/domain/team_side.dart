/// Which end of the court a team defends.
///
/// Deliberately separate from the team's *name*: the name is free text a coach
/// types in setup ("Ajax", "U18 Reds") and may be renamed at any time, while
/// the side is a geometric fact that positioning, rendering and the match
/// simulator all reason about. Conflating the two would mean renaming a team
/// silently changed which goal its players attack.
enum TeamSide {
  /// Defends `x = 0`, attacks `+x`.
  home('Home'),

  /// Defends `x = court.widthMeters`, attacks `-x`.
  away('Away');

  const TeamSide(this.displayName);

  /// Also the default team name until the user renames it.
  final String displayName;

  TeamSide get opposite => this == TeamSide.home ? TeamSide.away : TeamSide.home;
}
