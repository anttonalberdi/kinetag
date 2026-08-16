import 'package:meta/meta.dart';

import '../domain/domain.dart';
import 'analytics_thresholds.dart';
import 'court_presence.dart';
import 'possession.dart';
import 'session_metrics.dart';
import 'timeline_runs.dart';

/// The stretch of a recording a figure is measured over.
///
/// Every movement statistic in the app is a statement about *some* window of
/// time, and until now that window was always "the whole recording". Naming the
/// alternatives makes the choice explicit and, more usefully, makes it
/// selectable: the same table can report a session, a player's playing time, or
/// only the part of it their team spent attacking, without any of the
/// arithmetic changing.
enum PlaySplit {
  /// Everything recorded, bench time included. Rarely the figure a coach
  /// wants — it is here because the replay playhead reads speed from it, and
  /// because it is what the other splits must add up to.
  all('Whole recording', 'Bench time included.'),

  /// Only the spells the player was actually on the floor.
  onCourt('On court', 'Bench time excluded.'),

  /// Only the spells they were not.
  bench('On the bench', 'Time spent waiting to come on.'),

  /// On court while their own team had the ball.
  attacking('Attacking', 'On court while this team was attacking.'),

  /// On court while the other team had it.
  defending('Defending', 'On court while the other team was attacking.'),

  /// On court, but which way play was going could not be established.
  unclear('Unclear', 'On court with no phase established.');

  const PlaySplit(this.label, this.description);

  final String label;
  final String description;

  /// The splits a report offers a reader, in the order they are offered.
  ///
  /// [all], [bench] and [unclear] are deliberately absent: bench time is
  /// reported as time rather than as movement, and the other two exist for the
  /// arithmetic rather than for a coach.
  static const List<PlaySplit> selectable = [onCourt, attacking, defending];
}

/// One player's recording, split by what they were doing at the time.
///
/// The point of the split is that a statistic scoped to the wrong window is
/// misleading rather than merely imprecise. A substitute's average speed over
/// a whole match is mostly a measurement of sitting down; their distance per
/// minute *of play* is a measurement of them. Everything here is measured over
/// intervals, and the intervals are what differ.
///
/// The splits partition cleanly: [PlaySplit.onCourt] and [PlaySplit.bench]
/// cover [PlaySplit.all] between them, and [PlaySplit.attacking],
/// [PlaySplit.defending] and [PlaySplit.unclear] cover the on-court part. Sums
/// agree to within one sample per boundary — the instant of a switch is only
/// known to the resolution the tag reports at.
@immutable
class PlayerPlayMetrics {
  final String tagId;

  /// The end this player's team defends, or null when the roster did not say.
  /// Without it attacking and defending cannot be told apart for them.
  final TeamSide? side;

  final PlayerPresence presence;

  /// Movement metrics per split, all computed by the same arithmetic over
  /// different intervals.
  final Map<PlaySplit, PlayerTrackMetrics> bySplit;

  const PlayerPlayMetrics({
    required this.tagId,
    required this.side,
    required this.presence,
    required this.bySplit,
  });

  PlayerTrackMetrics forSplit(PlaySplit split) =>
      bySplit[split] ?? PlayerTrackMetrics.empty(tagId);

  /// Time measured in [split].
  ///
  /// Playing and bench time are read from the segmentation itself rather than
  /// from the samples that fell inside it. The two agree to within one sample
  /// per stint, and taking the segmentation's own answer is what keeps the
  /// headline "time on court" identical wherever it is shown — a figure a
  /// coach compares between players cannot wobble by a sample depending on
  /// which panel drew it.
  Duration durationOf(PlaySplit split) => switch (split) {
        PlaySplit.all => presence.trackedDuration,
        PlaySplit.onCourt => presence.onCourtDuration,
        PlaySplit.bench => presence.benchDuration,
        _ => forSplit(split).trackedDuration,
      };

  Duration get onCourtDuration => presence.onCourtDuration;
  Duration get benchDuration => presence.benchDuration;
  Duration get trackedDuration => presence.trackedDuration;
  int get stintCount => presence.stintCount;

  /// Whether attacking and defending could be told apart for this player at
  /// all — which needs both a side on the roster and a phase on the timeline.
  bool get hasPhaseSplit =>
      side != null &&
      (durationOf(PlaySplit.attacking) > Duration.zero ||
          durationOf(PlaySplit.defending) > Duration.zero);

  /// Share of [reference] spent on court, in 0..1.
  ///
  /// Takes the reference rather than assuming one, because both readings are
  /// legitimate and they answer different questions: against the session, "how
  /// much of the match did they play"; against their own tracked span, "how
  /// much of the time we were measuring them".
  double onCourtShareOf(Duration reference) {
    final total = reference.inMicroseconds;
    return total <= 0 ? 0 : onCourtDuration.inMicroseconds / total;
  }

  /// Share of the player's own on-court time spent in [split], in 0..1.
  double shareOfPlayingTime(PlaySplit split) {
    final total = onCourtDuration.inMicroseconds;
    return total <= 0 ? 0 : durationOf(split).inMicroseconds / total;
  }

  @override
  String toString() => 'PlayerPlayMetrics($tagId, '
      '${onCourtDuration.inSeconds} s on court, $stintCount stints)';
}

/// A whole recording, segmented into playing time and phases of play.
///
/// Pure Dart like everything else in this layer: it takes samples, the
/// session's own roster snapshot and the already-computed whole-recording
/// metrics, and returns figures. No storage, no providers, no Flutter, so the
/// segmentation can be tested against hand-built trajectories and reused from a
/// future export.
@immutable
class SessionPlayMetrics {
  final Map<String, PlayerPlayMetrics> byTagId;

  /// When each tag was on court.
  final SessionPresence presence;

  /// Which side was attacking, over time.
  final PossessionTimeline possession;

  /// What "the entire duration" means for the relative figures.
  ///
  /// The session's own recorded wall-clock span when it has a *finished* one,
  /// because that is the match a coach is thinking of and it counts the time
  /// nobody's tag was reporting. A recording still in progress measures its
  /// duration against the clock, which is not a figure an analysis can be
  /// divided by twice and get the same answer, so that case falls back to the
  /// longest span any tag was tracked for — as does a session that never
  /// recorded when it started.
  final Duration sessionDuration;

  final AnalyticsThresholds thresholds;
  final PlayThresholds playThresholds;

  const SessionPlayMetrics({
    required this.byTagId,
    required this.presence,
    required this.possession,
    required this.sessionDuration,
    this.thresholds = AnalyticsThresholds.defaults,
    this.playThresholds = PlayThresholds.defaults,
  });

  factory SessionPlayMetrics.empty(Court court) => SessionPlayMetrics(
        byTagId: const {},
        presence: SessionPresence(byTagId: const {}, court: court),
        possession: PossessionTimeline.unavailable,
        sessionDuration: Duration.zero,
      );

  /// Segments [samples] and measures each player over every split.
  ///
  /// [metrics] is the whole-recording result, taken rather than recomputed so
  /// that [PlaySplit.all] is the very same object the rest of the app already
  /// shows — the splits refine those figures, they never contradict them.
  factory SessionPlayMetrics.from({
    required SessionMetrics metrics,
    required Iterable<PositionSample> samples,
    required Session session,
    PlayThresholds playThresholds = PlayThresholds.defaults,
  }) {
    final tracks =
        SessionMetrics.groupByTag(samples, thresholds: metrics.thresholds);

    final presence = SessionPresence.fromTracks(
      tracks,
      court: session.court,
      thresholds: playThresholds,
    );
    final possession = PossessionTimeline.fromKeepers(
      tracks: tracks,
      session: session,
      presence: presence,
      thresholds: playThresholds,
    );

    var longestTracked = Duration.zero;
    final byTagId = <String, PlayerPlayMetrics>{};

    for (final entry in tracks.entries) {
      final tagId = entry.key;
      final track = entry.value;
      final playerPresence = presence.forTag(tagId);
      final side = session.playerForTag(tagId)?.side;

      if (playerPresence.trackedDuration > longestTracked) {
        longestTracked = playerPresence.trackedDuration;
      }

      final onCourt = _rangesOf(
        playerPresence.stints,
        (value) => value == CourtPresence.onCourt,
      );
      final bench = _rangesOf(
        playerPresence.stints,
        (value) => value == CourtPresence.bench,
      );
      final phases = possession.phasesFor(side);

      PlayerTrackMetrics measure(List<(int, int)> ranges) =>
          PlayerTrackMetrics.merged(tagId, [
            for (final segment in _segmentsWithin(track, ranges))
              SessionMetrics.forTrack(
                tagId,
                segment,
                thresholds: metrics.thresholds,
              ),
          ]);

      List<(int, int)> onCourtDuring(PlayPhase phase) => _intersect(
            onCourt,
            _rangesOf(phases, (value) => value == phase),
          );

      final attacking = onCourtDuring(PlayPhase.attacking);
      final defending = onCourtDuring(PlayPhase.defending);

      // Whatever playing time the two phases did not claim, rather than the
      // stretches the timeline explicitly labelled unclear. The difference
      // matters when there is no timeline at all — no goalkeeper on the
      // roster, or none tracked — where there are no stretches to label and
      // the whole of a player's time would otherwise fall through the split
      // and quietly vanish from the totals.
      final unclear = _subtract(
        onCourt,
        [...attacking, ...defending]..sort((a, b) => a.$1.compareTo(b.$1)),
      );

      byTagId[tagId] = PlayerPlayMetrics(
        tagId: tagId,
        side: side,
        presence: playerPresence,
        bySplit: {
          PlaySplit.all:
              metrics.forTag(tagId) ?? PlayerTrackMetrics.empty(tagId),
          PlaySplit.onCourt: measure(onCourt),
          PlaySplit.bench: measure(bench),
          PlaySplit.attacking: measure(attacking),
          PlaySplit.defending: measure(defending),
          PlaySplit.unclear: measure(unclear),
        },
      );
    }

    return SessionPlayMetrics(
      byTagId: byTagId,
      presence: presence,
      possession: possession,
      sessionDuration: session.stoppedAt == null
          ? longestTracked
          : (session.duration ?? longestTracked),
      thresholds: metrics.thresholds,
      playThresholds: playThresholds,
    );
  }

  PlayerPlayMetrics? forTag(String tagId) => byTagId[tagId];

  bool get isEmpty => byTagId.isEmpty;

  /// Every player's metrics for [split], for handing to `SessionTeamMetrics`.
  List<PlayerTrackMetrics> tracksFor(PlaySplit split) =>
      [for (final player in byTagId.values) player.forSplit(split)];

  /// Whether anybody was ever seen off the playing surface — the question
  /// worth asking before showing a bench column that is zero for everyone.
  bool get hasBenchTime => presence.hasBenchTime;

  /// Whether attacking and defending could be told apart at all.
  bool get hasPhases => possession.isAvailable;

  /// Combined on-court time of every tracked player.
  Duration get totalPlayingTime => Duration(
        microseconds: byTagId.values.fold(
          0,
          (sum, player) => sum + player.onCourtDuration.inMicroseconds,
        ),
      );

  /// Combined bench time of every tracked player.
  Duration get totalBenchTime => Duration(
        microseconds: byTagId.values.fold(
          0,
          (sum, player) => sum + player.benchDuration.inMicroseconds,
        ),
      );

  /// Half-open ranges of the runs [keep] accepts.
  ///
  /// The final range is closed a microsecond late so that the last sample of a
  /// recording falls inside it. Without that the closing sample belongs to no
  /// range at all, since every other boundary is exclusive.
  static List<(int, int)> _rangesOf<T>(
    List<TimedRun<T>> runs,
    bool Function(T value) keep,
  ) {
    final ranges = <(int, int)>[];
    for (var i = 0; i < runs.length; i++) {
      if (!keep(runs[i].value)) continue;
      final isLast = i == runs.length - 1;
      ranges.add((runs[i].startMicros, runs[i].endMicros + (isLast ? 1 : 0)));
    }
    return ranges;
  }

  /// Everything in [a] that [b] does not cover. Both are ordered and disjoint.
  static List<(int, int)> _subtract(List<(int, int)> a, List<(int, int)> b) {
    final result = <(int, int)>[];
    var skip = 0;

    for (final (rangeStart, rangeEnd) in a) {
      var start = rangeStart;
      while (skip < b.length && b[skip].$2 <= start) {
        skip++;
      }
      for (var i = skip; i < b.length && b[i].$1 < rangeEnd; i++) {
        if (b[i].$1 > start) result.add((start, b[i].$1));
        if (b[i].$2 > start) start = b[i].$2;
      }
      if (start < rangeEnd) result.add((start, rangeEnd));
    }

    return result;
  }

  /// The overlap of two ordered, disjoint range lists.
  static List<(int, int)> _intersect(List<(int, int)> a, List<(int, int)> b) {
    final result = <(int, int)>[];
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      final start = a[i].$1 > b[j].$1 ? a[i].$1 : b[j].$1;
      final end = a[i].$2 < b[j].$2 ? a[i].$2 : b[j].$2;
      if (start < end) result.add((start, end));
      if (a[i].$2 < b[j].$2) {
        i++;
      } else {
        j++;
      }
    }
    return result;
  }

  /// Cuts [track] into the runs of samples falling inside [ranges].
  ///
  /// The ranges are ordered and disjoint, so one cursor walks the track once
  /// however many of them there are. Each run is measured on its own and the
  /// results added, which is what keeps a player's distance from being
  /// integrated across the minutes they spent sitting down.
  static List<List<PositionSample>> _segmentsWithin(
    List<PositionSample> track,
    List<(int, int)> ranges,
  ) {
    final segments = <List<PositionSample>>[];
    var cursor = 0;

    for (final (start, end) in ranges) {
      while (cursor < track.length &&
          track[cursor].timestampMicros < start) {
        cursor++;
      }
      final from = cursor;
      while (cursor < track.length && track[cursor].timestampMicros < end) {
        cursor++;
      }
      if (cursor - from >= 1) segments.add(track.sublist(from, cursor));
    }

    return segments;
  }
}
