import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import '../../domain/domain.dart';

/// Everything needed to draw one tracked tag: who is wearing it, what to
/// print on the marker, and in which team colour.
///
/// The laid-out [labelPainter] is built once, when the roster is built, and
/// reused for every frame. Laying out text is the most expensive thing a
/// per-tag painter does; at twelve tags and 20 Hz, doing it on the render
/// path would mean 240 text layouts a second for labels that never change.
@immutable
class TagRosterEntry {
  final String tagId;
  final String playerName;
  final String? team;

  /// Short on-court label: shirt number, or initials when there is none.
  final String label;

  final Color color;
  final TextPainter labelPainter;

  TagRosterEntry({
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
class TagRoster {
  final List<Player> players;
  final List<Tag> tags;
  final List<TagAssignment> assignments;
  final List<Team> teams;
  final Map<String, TagRosterEntry> byTagId;

  const TagRoster({
    required this.players,
    required this.tags,
    required this.assignments,
    required this.byTagId,
    this.teams = const [],
  });

  /// The palette a team's colour is chosen from, in display form.
  ///
  /// `final` rather than `const` because it is derived from the domain's
  /// packed-int palette — the single place a colour is declared.
  static final List<Color> teamColors = List.unmodifiable(
    [for (final value in Team.colorPalette) Color(value)],
  );

  /// Colour for a tag with no known player.
  static const Color unassignedColor = Color(Team.unassignedColorValue);

  /// Builds the on-court appearance from a setup or a session snapshot.
  ///
  /// [teams] carries the colour each side was given. It is optional because a
  /// session recorded before teams were user-defined has none; those fall back
  /// to colouring by the order team names appear among the players, which is
  /// what such a recording was captured under.
  factory TagRoster.fromSetup({
    required List<Player> players,
    required List<Tag> tags,
    required List<TagAssignment> assignments,
    List<Team> teams = const [],
  }) {
    final teamBySide = {for (final team in teams) team.side: team};

    // Legacy fallback only. Team order is taken from the player list rather
    // than sorted alphabetically, so the first side keeps its colour when the
    // other is renamed.
    final teamOrder = <String>[];
    if (teams.isEmpty) {
      for (final player in players) {
        final name = player.team;
        if (name != null && !teamOrder.contains(name)) teamOrder.add(name);
      }
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

    Color colorFor(Player? player) {
      if (player == null) return unassignedColor;

      final side = player.side;
      if (side != null) {
        final team = teamBySide[side];
        if (team != null) return Color(team.colorValue);
      }

      final index = player.team == null ? -1 : teamOrder.indexOf(player.team!);
      return index < 0 ? unassignedColor : teamColors[index % teamColors.length];
    }

    final byTagId = <String, TagRosterEntry>{};
    for (final tag in tags) {
      final player = playerFor(tag.id);
      // The team record is authoritative for the name: a player's `team`
      // string is a copy that a rename updates, and preferring the record
      // means a stale copy can never surface in the legend.
      final teamName =
          teamBySide[player?.side]?.name ?? player?.team;

      byTagId[tag.id] = TagRosterEntry(
        tagId: tag.id,
        playerName: player?.name ?? tag.name,
        team: teamName,
        label: player?.shortLabel ?? _tagFallbackLabel(tag),
        color: colorFor(player),
      );
    }

    return TagRoster(
      players: players,
      tags: tags,
      assignments: assignments,
      teams: teams,
      byTagId: byTagId,
    );
  }

  /// The appearance for [tagId], or null for a tag that is not in the roster
  /// — which happens when hardware reports a tag nobody has registered yet.
  TagRosterEntry? entryFor(String tagId) => byTagId[tagId];

  /// Player names in team order, for the live legend.
  Iterable<TagRosterEntry> get entries => [
        for (final tag in tags)
          if (byTagId.containsKey(tag.id)) byTagId[tag.id]!,
      ];

  static String _tagFallbackLabel(Tag tag) {
    final id = tag.hardwareId.isNotEmpty ? tag.hardwareId : tag.id;
    return id.length <= 3 ? id : id.substring(id.length - 3);
  }
}
