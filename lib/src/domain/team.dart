import 'package:meta/meta.dart';

import 'team_side.dart';

/// A team taking part in a session: which end it defends, what it is called,
/// and the colour its players are drawn in.
///
/// ## Why the colour lives here
///
/// Colour used to be assigned implicitly by the order teams appeared in the
/// player list. Once a coach can choose it, it becomes data — and data a
/// recording must snapshot, for the same reason receiver positions are
/// snapshotted: reopening a session months later must show the sides the way
/// they were captured, not the way the setup screen happens to be configured
/// now.
///
/// ## Why it is an `int`, not a `Color`
///
/// `Color` comes from `dart:ui`. The domain layer is pure Dart so it stays
/// usable from a headless hub process with no Flutter engine, so the colour is
/// carried as a packed `0xAARRGGBB` value and converted at the UI boundary.
@immutable
class Team {
  final TeamSide side;
  final String name;

  /// Packed `0xAARRGGBB`.
  final int colorValue;

  const Team({
    required this.side,
    required this.name,
    required this.colorValue,
  });

  /// Colours offered in setup.
  ///
  /// Chosen to stay distinguishable against the dark court and from each
  /// other, including for the commonest forms of colour blindness — two sides
  /// that read alike on screen make a live view useless.
  static const List<int> colorPalette = [
    0xFF5AA9FF, // blue
    0xFFFF9445, // orange
    0xFF67D68A, // green
    0xFFD98CFF, // violet
    0xFFFFD166, // amber
    0xFFFF6B6B, // red
    0xFF4ECDC4, // teal
    0xFFE9EEF3, // white
  ];

  /// Colour a tag takes when no team owns it.
  static const int unassignedColorValue = 0xFFB9C4CF;

  /// The default colour for [side]: blue for home, orange for away.
  static int defaultColorFor(TeamSide side) => colorPalette[side.index];

  /// A team named and coloured after the side it defends.
  factory Team.defaults(TeamSide side) => Team(
        side: side,
        name: side.displayName,
        colorValue: defaultColorFor(side),
      );

  Team copyWith({TeamSide? side, String? name, int? colorValue}) => Team(
        side: side ?? this.side,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
      );

  Map<String, dynamic> toJson() => {
        'side': side.name,
        'name': name,
        'colorValue': colorValue,
      };

  factory Team.fromJson(Map<String, dynamic> json) {
    final side = TeamSide.values.byName(json['side'] as String);
    return Team(
      side: side,
      name: json['name'] as String,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? defaultColorFor(side),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Team &&
          other.side == side &&
          other.name == name &&
          other.colorValue == colorValue;

  @override
  int get hashCode => Object.hash(side, name, colorValue);

  @override
  String toString() => 'Team($name, ${side.displayName})';
}
