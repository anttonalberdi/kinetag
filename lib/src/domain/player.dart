import 'package:meta/meta.dart';

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

  final String? team;

  /// Reserved for future metadata (position/role, height, dominant hand).
  final Map<String, dynamic> metadata;

  const Player({
    required this.id,
    required this.name,
    this.number,
    this.team,
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
    String? team,
    Map<String, dynamic>? metadata,
  }) =>
      Player(
        id: id ?? this.id,
        name: name ?? this.name,
        number: number ?? this.number,
        team: team ?? this.team,
        metadata: metadata ?? this.metadata,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'number': number,
        'team': team,
        'metadata': metadata,
      };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        name: json['name'] as String,
        number: json['number'] as int?,
        team: json['team'] as String?,
        metadata: Map<String, dynamic>.from(
            json['metadata'] as Map? ?? const <String, dynamic>{}),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Player &&
          other.id == id &&
          other.name == name &&
          other.number == number &&
          other.team == team;

  @override
  int get hashCode => Object.hash(id, name, number, team);

  @override
  String toString() => 'Player($name${number != null ? ' #$number' : ''})';
}
