import 'package:meta/meta.dart';

/// Where on the player's body a tag is mounted.
///
/// Kinetag's target hardware is shoe-mounted, with a longer-term goal of two
/// tags per player enabling gait/step analysis and a more accurate player
/// centre. The prototype uses one tag per player, but the model carries the
/// mount location from the start so that adding the second shoe later is a
/// data change rather than a schema migration.
enum TagMountLocation {
  leftShoe('Left shoe'),
  rightShoe('Right shoe'),
  unknown('Unknown');

  const TagMountLocation(this.displayName);

  final String displayName;
}

/// Binds one [Tag] to one [Player] at a given mount location.
///
/// A player may hold several assignments simultaneously (left + right shoe).
/// Assignments are snapshotted into a `Session` so that later re-assignment of
/// hardware does not rewrite the meaning of historical recordings.
@immutable
class TagAssignment {
  final String id;
  final String playerId;
  final String tagId;
  final TagMountLocation location;

  const TagAssignment({
    required this.id,
    required this.playerId,
    required this.tagId,
    this.location = TagMountLocation.unknown,
  });

  TagAssignment copyWith({
    String? id,
    String? playerId,
    String? tagId,
    TagMountLocation? location,
  }) =>
      TagAssignment(
        id: id ?? this.id,
        playerId: playerId ?? this.playerId,
        tagId: tagId ?? this.tagId,
        location: location ?? this.location,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'playerId': playerId,
        'tagId': tagId,
        'location': location.name,
      };

  factory TagAssignment.fromJson(Map<String, dynamic> json) => TagAssignment(
        id: json['id'] as String,
        playerId: json['playerId'] as String,
        tagId: json['tagId'] as String,
        location: TagMountLocation.values.byName(json['location'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagAssignment &&
          other.id == id &&
          other.playerId == playerId &&
          other.tagId == tagId &&
          other.location == location;

  @override
  int get hashCode => Object.hash(id, playerId, tagId, location);

  @override
  String toString() =>
      'TagAssignment(player=$playerId, tag=$tagId, ${location.displayName})';
}
