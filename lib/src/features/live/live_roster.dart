import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../domain/domain.dart';
import '../../tracking/tracking_providers.dart';

/// Everything needed to draw one tracked tag: who is wearing it, what to
/// print on the marker, and in which team colour.
///
/// The laid-out [labelPainter] is built once, when the roster is built, and
/// reused for every frame. Laying out text is the most expensive thing a
/// per-tag painter does; at twelve tags and 20 Hz, doing it on the render
/// path would mean 240 text layouts a second for labels that never change.
@immutable
class LiveRosterEntry {
  final String tagId;
  final String playerName;
  final String? team;

  /// Short on-court label: shirt number, or initials when there is none.
  final String label;

  final Color color;
  final TextPainter labelPainter;

  LiveRosterEntry({
    required this.tagId,
    required this.playerName,
    required this.team,
    required this.label,
    required this.color,
  }) : labelPainter = _paintedLabel(label);

  static TextPainter _paintedLabel(String label) => TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF0C1015),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
}

/// Maps tag ids to their on-court appearance.
///
/// Built from plain domain objects — players, tags and assignments — so it
/// works identically for a simulated squad and, later, for a real roster
/// entered in setup.
@immutable
class LiveRoster {
  final List<Player> players;
  final List<Tag> tags;
  final List<TagAssignment> assignments;
  final Map<String, LiveRosterEntry> byTagId;

  const LiveRoster({
    required this.players,
    required this.tags,
    required this.assignments,
    required this.byTagId,
  });

  /// Colour per team, in the order teams first appear.
  static const List<Color> teamColors = [
    Color(0xFF5AA9FF),
    Color(0xFFFF9445),
    Color(0xFF67D68A),
    Color(0xFFD98CFF),
  ];

  /// Colour for a tag with no known player.
  static const Color unassignedColor = Color(0xFFB9C4CF);

  factory LiveRoster.fromSetup({
    required List<Player> players,
    required List<Tag> tags,
    required List<TagAssignment> assignments,
  }) {
    // Team order is taken from the player list rather than sorted
    // alphabetically, so "Home" keeps its colour when an away side is renamed.
    final teamOrder = <String>[];
    for (final player in players) {
      final team = player.team;
      if (team != null && !teamOrder.contains(team)) teamOrder.add(team);
    }

    Player? playerFor(String tagId) {
      for (final assignment in assignments) {
        if (assignment.tagId != tagId) continue;
        for (final player in players) {
          if (player.id == assignment.playerId) return player;
        }
      }
      return null;
    }

    final byTagId = <String, LiveRosterEntry>{};
    for (final tag in tags) {
      final player = playerFor(tag.id);
      final teamIndex = player?.team == null ? -1 : teamOrder.indexOf(player!.team!);

      byTagId[tag.id] = LiveRosterEntry(
        tagId: tag.id,
        playerName: player?.name ?? tag.name,
        team: player?.team,
        label: player?.shortLabel ?? _tagFallbackLabel(tag),
        color: teamIndex < 0
            ? unassignedColor
            : teamColors[teamIndex % teamColors.length],
      );
    }

    return LiveRoster(
      players: players,
      tags: tags,
      assignments: assignments,
      byTagId: byTagId,
    );
  }

  /// The appearance for [tagId], or null for a tag that is not in the roster
  /// — which happens when hardware reports a tag nobody has registered yet.
  LiveRosterEntry? entryFor(String tagId) => byTagId[tagId];

  /// Player names in team order, for the live legend.
  Iterable<LiveRosterEntry> get entries => [
        for (final tag in tags)
          if (byTagId.containsKey(tag.id)) byTagId[tag.id]!,
      ];

  static String _tagFallbackLabel(Tag tag) {
    final id = tag.hardwareId.isNotEmpty ? tag.hardwareId : tag.id;
    return id.length <= 3 ? id : id.substring(id.length - 3);
  }
}

/// The roster the live view labels frames with.
///
/// Sourced from the simulated squad for now. When real tags arrive this is
/// the one line that changes: the players, tags and assignments will come
/// from setup instead, and everything downstream already speaks the domain
/// types.
final liveRosterProvider = Provider<LiveRoster>((ref) {
  final squad = ref.watch(simulatedSquadProvider);
  return LiveRoster.fromSetup(
    players: squad.players,
    tags: squad.tags,
    assignments: squad.assignments,
  );
});
