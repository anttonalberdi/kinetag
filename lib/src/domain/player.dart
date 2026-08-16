import 'package:meta/meta.dart';

import 'player_role.dart';
import 'team_side.dart';

/// A human player.
///
/// A player is never permanently bound to a tag — that relationship lives in
/// `TagAssignment` and is scoped to a session.
@immutable
class Player {
  final String id;
  final String name;

  /// Shirt number. Nullable because a player may be registered before being
  /// assigned one.
  final int? number;

  /// Free-text team name as entered in setup ("Home", "Ajax", "U18 Reds").
  final String? team;

  /// Which end of the court this player's team defends.
  ///
  /// Stored alongside [team] rather than derived from it: [team] is a label
  /// the user may rename mid-setup, while the side is what the simulator and
  /// any future tactical analytics reason about geometrically.
  final TeamSide? side;

  /// Position in the formation, assigned in setup. Null for a player whose
  /// role has not been set.
  final PlayerRole? role;

  /// Reserved for future metadata (height, dominant hand, squad number).
  final Map<String, dynamic> metadata;

  const Player({
    required this.id,
    required this.name,
    this.number,
    this.team,
    this.side,
    this.role,
    this.metadata = const {},
  });

  /// Short label for on-court rendering: the shirt number when available,
  /// otherwise the player's initials.
  String get shortLabel {
    if (number != null) return '$number';
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.map((p) => p[0].toUpperCase()).take(2).join();
  }

  Player copyWith({
    String? id,
    String? name,
    int? number,
    bool clearNumber = false,
    String? team,
    TeamSide? side,
    PlayerRole? role,
    bool clearRole = false,
    Map<String, dynamic>? metadata,
  }) =>
      Player(
        id: id ?? this.id,
        name: name ?? this.name,
        number: clearNumber ? null : (number ?? this.number),
        team: team ?? this.team,
        side: side ?? this.side,
        role: clearRole ? null : (role ?? this.role),
        metadata: metadata ?? this.metadata,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'number': number,
        'team': team,
        'side': side?.name,
        'role': role?.name,
        'metadata': metadata,
      };

  factory Player.fromJson(Map<String, dynamic> json) {
    final metadata = Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const <String, dynamic>{});

    // Sessions recorded before roles became a typed field carried the role in
    // `metadata`. Reading it back keeps those recordings meaningful instead of
    // silently losing the roster they were captured with.
    final roleName = json['role'] as String? ?? metadata['role'] as String?;

    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      number: json['number'] as int?,
      team: json['team'] as String?,
      side: _enumOrNull(TeamSide.values, json['side'] as String?),
      role: _enumOrNull(PlayerRole.values, roleName),
      metadata: metadata,
    );
  }

  /// Looks up an enum value by name, tolerating null and unknown names.
  ///
  /// Unknown rather than throwing: a session recorded by a newer build may
  /// name a role this one does not have, and losing the player's role is a
  /// far better outcome than failing to open the recording at all.
  static T? _enumOrNull<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Player &&
          other.id == id &&
          other.name == name &&
          other.number == number &&
          other.team == team &&
          other.side == side &&
          other.role == role;

  @override
  int get hashCode => Object.hash(id, name, number, team, side, role);

  @override
  String toString() => 'Player($name${number != null ? ' #$number' : ''})';
}
