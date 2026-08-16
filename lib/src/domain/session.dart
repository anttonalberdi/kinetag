import 'package:meta/meta.dart';

import 'court.dart';
import 'player.dart';
import 'receiver.dart';
import 'tag.dart';
import 'tag_assignment.dart';

enum SessionStatus {
  /// Created but never started.
  draft('Draft'),

  /// Currently capturing samples.
  recording('Recording'),

  /// Finished; recorded data is complete and immutable.
  completed('Completed'),

  /// Started but ended abnormally (e.g. app closed mid-recording).
  aborted('Aborted');

  const SessionStatus(this.displayName);

  final String displayName;
}

/// A recording session together with a frozen copy of the setup that produced
/// it.
///
/// ## Why the setup is snapshotted
///
/// [court], [receivers], [tags], [players] and [tagAssignments] are stored
/// **by value**, not by reference to the live setup. Recorded trajectories are
/// only interpretable against the anchor geometry that produced them: if a
/// receiver is later moved 3 m in the setup screen, a historical session's
/// positions do not change, and its inspector must keep showing where the
/// receiver actually stood at capture time. Referencing mutable setup objects
/// would silently corrupt the meaning of every past recording.
///
/// ## Reprocessing
///
/// [positioningAlgorithmVersion] records which positioning implementation
/// produced the stored trajectories. Once raw UWB measurements are also
/// recorded, a session can be reprocessed with a newer algorithm and the
/// result distinguished from the original.
@immutable
class Session {
  final String id;
  final String name;
  final DateTime createdAt;

  /// Frozen setup snapshot.
  final Court court;
  final List<Receiver> receivers;
  final List<Tag> tags;
  final List<Player> players;
  final List<TagAssignment> tagAssignments;

  final SessionStatus status;

  /// Wall-clock instant recording began; null while still a draft.
  final DateTime? startedAt;

  /// Wall-clock instant recording ended; null while in progress.
  final DateTime? stoppedAt;

  /// Number of position samples persisted for this session. Cached because
  /// counting rows on a multi-hour recording is expensive and the session
  /// list needs it.
  final int sampleCount;

  /// Identifier of the positioning implementation that produced the stored
  /// trajectories. `simulator-v1` for simulated sessions.
  final String positioningAlgorithmVersion;

  const Session({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.court,
    this.receivers = const [],
    this.tags = const [],
    this.players = const [],
    this.tagAssignments = const [],
    this.status = SessionStatus.draft,
    this.startedAt,
    this.stoppedAt,
    this.sampleCount = 0,
    this.positioningAlgorithmVersion = 'simulator-v1',
  });

  /// Wall-clock duration of the recording, or null if it never started.
  ///
  /// While recording is in progress this measures against [DateTime.now],
  /// so callers that need a stable value should read it once per UI tick.
  Duration? get duration {
    if (startedAt == null) return null;
    final end = stoppedAt ?? DateTime.now().toUtc();
    return end.difference(startedAt!);
  }

  bool get isRecording => status == SessionStatus.recording;
  bool get hasRecordedData =>
      status == SessionStatus.completed && sampleCount > 0;

  /// The player wearing [tagId] in this session, or null if unassigned.
  Player? playerForTag(String tagId) {
    for (final assignment in tagAssignments) {
      if (assignment.tagId == tagId) {
        for (final player in players) {
          if (player.id == assignment.playerId) return player;
        }
      }
    }
    return null;
  }

  /// All assignments belonging to [playerId] — up to two once both shoes are
  /// tagged.
  List<TagAssignment> assignmentsForPlayer(String playerId) =>
      tagAssignments.where((a) => a.playerId == playerId).toList();

  Session copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    Court? court,
    List<Receiver>? receivers,
    List<Tag>? tags,
    List<Player>? players,
    List<TagAssignment>? tagAssignments,
    SessionStatus? status,
    DateTime? startedAt,
    DateTime? stoppedAt,
    int? sampleCount,
    String? positioningAlgorithmVersion,
  }) =>
      Session(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        court: court ?? this.court,
        receivers: receivers ?? this.receivers,
        tags: tags ?? this.tags,
        players: players ?? this.players,
        tagAssignments: tagAssignments ?? this.tagAssignments,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        stoppedAt: stoppedAt ?? this.stoppedAt,
        sampleCount: sampleCount ?? this.sampleCount,
        positioningAlgorithmVersion:
            positioningAlgorithmVersion ?? this.positioningAlgorithmVersion,
      );

  /// Serialises the setup snapshot. Position samples are *not* included —
  /// they are stored separately so that a multi-hour recording never has to
  /// be loaded into memory just to list sessions.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'court': court.toJson(),
        'receivers': receivers.map((r) => r.toJson()).toList(),
        'tags': tags.map((t) => t.toJson()).toList(),
        'players': players.map((p) => p.toJson()).toList(),
        'tagAssignments': tagAssignments.map((a) => a.toJson()).toList(),
        'status': status.name,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'stoppedAt': stoppedAt?.toUtc().toIso8601String(),
        'sampleCount': sampleCount,
        'positioningAlgorithmVersion': positioningAlgorithmVersion,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        court: Court.fromJson(json['court'] as Map<String, dynamic>),
        receivers: (json['receivers'] as List? ?? [])
            .map((r) => Receiver.fromJson(r as Map<String, dynamic>))
            .toList(),
        tags: (json['tags'] as List? ?? [])
            .map((t) => Tag.fromJson(t as Map<String, dynamic>))
            .toList(),
        players: (json['players'] as List? ?? [])
            .map((p) => Player.fromJson(p as Map<String, dynamic>))
            .toList(),
        tagAssignments: (json['tagAssignments'] as List? ?? [])
            .map((a) => TagAssignment.fromJson(a as Map<String, dynamic>))
            .toList(),
        status: SessionStatus.values.byName(json['status'] as String),
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.parse(json['startedAt'] as String),
        stoppedAt: json['stoppedAt'] == null
            ? null
            : DateTime.parse(json['stoppedAt'] as String),
        sampleCount: json['sampleCount'] as int? ?? 0,
        positioningAlgorithmVersion:
            json['positioningAlgorithmVersion'] as String? ?? 'unknown',
      );

  @override
  String toString() =>
      'Session($name, ${status.displayName}, $sampleCount samples)';
}
