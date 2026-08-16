import 'package:meta/meta.dart';

import '../domain/domain.dart';
import 'analytics_thresholds.dart';
import 'session_metrics.dart';
import 'speed_zones.dart';

/// Movement for one side of a session, aggregated from its players' tracks.
///
/// A team figure is only ever the sum or the mean of the individual tracks it
/// was built from, never a separate measurement: the samples remain the single
/// source of truth, and a coach comparing a player with their team must be
/// comparing two views of the same arithmetic.
@immutable
class TeamMetrics {
  /// What to call this group: the team's name, or "Unassigned" for tags whose
  /// wearer has no team.
  final String label;

  /// The end of the court this team defends, when the session recorded one.
  final TeamSide? side;

  /// Players on this team, ranked by distance covered.
  final List<PlayerTrackMetrics> tracks;

  /// The team's time by intensity — every player's bands added together, so a
  /// squad of twelve reports twelve player-minutes per minute of play.
  final SpeedZoneBreakdown zones;

  const TeamMetrics({
    required this.label,
    required this.side,
    required this.tracks,
    required this.zones,
  });

  int get playerCount => tracks.length;

  double get totalDistanceMeters =>
      tracks.fold(0.0, (sum, track) => sum + track.distanceMeters);

  /// Distance per player: the figure to compare two squads of different sizes
  /// with, which the total cannot do.
  double get averageDistanceMeters =>
      tracks.isEmpty ? 0 : totalDistanceMeters / tracks.length;

  /// Mean of the players' own average speeds.
  ///
  /// Each player weighs the same regardless of how long they were tracked,
  /// which is what makes it a statement about the team rather than about who
  /// happened to be on court longest.
  double get averageSpeedMps => tracks.isEmpty
      ? 0
      : tracks.fold(0.0, (sum, track) => sum + track.averageSpeedMps) /
            tracks.length;

  /// The fastest single moment anyone on this team reached.
  PlayerTrackMetrics? get fastest {
    PlayerTrackMetrics? best;
    for (final track in tracks) {
      if (best == null || track.maxSpeedMps > best.maxSpeedMps) best = track;
    }
    return best;
  }

  double get maxSpeedMps => fastest?.maxSpeedMps ?? 0;

  bool contains(String tagId) => tracks.any((track) => track.tagId == tagId);
}

/// A whole session split by team, plus the session-wide totals.
///
/// Pure Dart like [SessionMetrics]: it takes the per-player metrics and the
/// session's own roster snapshot, so a recording is always grouped by the
/// teams it was captured with rather than by whatever setup holds today.
@immutable
class SessionTeamMetrics {
  /// Home first, then away, then teams with no side, and unassigned tags last
  /// — the order a coach reads a scoreboard in.
  final List<TeamMetrics> teams;

  /// Every track in the session, ranked by distance covered.
  final List<PlayerTrackMetrics> ranked;

  /// Intensity bands per tag, computed once here because the ranking table,
  /// the team bars and the player page all want them.
  final Map<String, SpeedZoneBreakdown> zonesByTag;

  /// The noise-rejection settings every figure here was produced under,
  /// carried on for the same reason [SessionMetrics] carries them.
  final AnalyticsThresholds thresholds;

  const SessionTeamMetrics({
    required this.teams,
    required this.ranked,
    required this.zonesByTag,
    this.thresholds = AnalyticsThresholds.defaults,
  });

  static const String unassignedLabel = 'Unassigned';

  factory SessionTeamMetrics.from({
    required SessionMetrics metrics,
    required Session session,
  }) {
    final ranked = metrics.byDistance;
    final zonesByTag = {
      for (final track in ranked)
        track.tagId: SpeedZoneBreakdown.fromTrack(track),
    };

    final grouped = <String, List<PlayerTrackMetrics>>{};
    final labels = <String, String>{};
    final sides = <String, TeamSide?>{};

    for (final track in ranked) {
      final player = session.playerForTag(track.tagId);
      final side = player?.side;
      // The team record is authoritative for the name; a player's own `team`
      // string is a copy, and is all a session recorded before teams were
      // snapshotted has.
      final name =
          (side == null ? null : session.teamFor(side)?.name) ?? player?.team;

      // Grouping by side when there is one, by name otherwise: two players
      // whose team was renamed mid-setup still belong to the same side.
      final key = side?.name ?? name ?? unassignedLabel;
      (grouped[key] ??= []).add(track);
      labels[key] = name ?? unassignedLabel;
      sides[key] = side;
    }

    final keys = grouped.keys.toList()
      ..sort((a, b) {
        final rank = _sortRank(
          sides[a],
          labels[a]!,
        ).compareTo(_sortRank(sides[b], labels[b]!));
        return rank != 0 ? rank : labels[a]!.compareTo(labels[b]!);
      });

    return SessionTeamMetrics(
      teams: [
        for (final key in keys)
          TeamMetrics(
            label: labels[key]!,
            side: sides[key],
            tracks: grouped[key]!,
            zones: SpeedZoneBreakdown.merged([
              for (final track in grouped[key]!) zonesByTag[track.tagId]!,
            ]),
          ),
      ],
      ranked: ranked,
      zonesByTag: zonesByTag,
      thresholds: metrics.thresholds,
    );
  }

  bool get isEmpty => ranked.isEmpty;

  int get playerCount => ranked.length;

  double get totalDistanceMeters =>
      ranked.fold(0.0, (sum, track) => sum + track.distanceMeters);

  double get averageDistanceMeters =>
      ranked.isEmpty ? 0 : totalDistanceMeters / ranked.length;

  /// The fastest moment of the whole session, and who reached it.
  PlayerTrackMetrics? get fastest => ranked.isEmpty
      ? null
      : ranked.reduce((a, b) => a.maxSpeedMps >= b.maxSpeedMps ? a : b);

  /// Combined time every tracked player spent in [zone].
  Duration timeIn(SpeedZone zone) => zonesByTag.values.fold(
    Duration.zero,
    (sum, breakdown) => sum + breakdown.inZone(zone),
  );

  /// The longest span any one tag was tracked for — the closest thing to
  /// "how long the session ran" that is derived from the samples themselves.
  Duration get trackedDuration => ranked.fold(
    Duration.zero,
    (longest, track) =>
        track.trackedDuration > longest ? track.trackedDuration : longest,
  );

  TeamMetrics? teamOf(String tagId) {
    for (final team in teams) {
      if (team.contains(tagId)) return team;
    }
    return null;
  }

  /// 1-based position of [tagId] in the distance ranking, or 0 if unknown.
  int rankOf(String tagId) =>
      ranked.indexWhere((track) => track.tagId == tagId) + 1;

  static int _sortRank(TeamSide? side, String label) {
    if (side != null) return side.index;
    return label == unassignedLabel ? 3 : 2;
  }
}
