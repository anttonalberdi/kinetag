import 'package:meta/meta.dart';

import '../domain/domain.dart';
import 'analytics_thresholds.dart';
import 'timeline_runs.dart';

/// Whether a tag was taking part or sitting out.
enum CourtPresence {
  onCourt('On court'),
  bench('Bench');

  const CourtPresence(this.label);

  final String label;
}

/// When one tag was playing and when it was not.
///
/// ## How it is decided
///
/// Geometrically, from where the tag was: a player on the bench is off the
/// playing surface, and a player taking part is on it. Nothing else is needed —
/// no manual line-up entry, no clock a coach has to remember to press — which
/// matters because the substitution log is exactly the record nobody keeps
/// during a match.
///
/// The naive version of that test flickers. A wing stands a hand's width inside
/// the sideline and positioning error of a few centimetres would put them
/// alternately on and off it many times a second, so two rules protect it:
///
/// 1. **Hysteresis.** Coming on requires being
///    [PlayThresholds.onCourtInsetMeters] *inside* the lines; going off
///    requires being [PlayThresholds.offCourtMarginMeters] *outside* them.
///    Between the two the previous state simply holds.
/// 2. **A minimum stint.** Spells shorter than [PlayThresholds.minStint] are
///    absorbed into the spell before them — see [buildRuns]. This is what keeps
///    a throw-in taken from behind the sideline out of the substitution count.
///
/// ## What it costs
///
/// The instant of a substitution is only known to within one sample, and the
/// walk to the bench is credited to the state the player is leaving. At 20 Hz
/// that is a rounding error against a stint measured in minutes; it is stated
/// because a figure derived from this — time on court, and every per-minute
/// rate built on it — inherits that uncertainty.
@immutable
class PlayerPresence {
  final String tagId;

  /// Alternating on-court and bench spells, in time order, partitioning the
  /// span this tag was tracked for.
  final List<TimedRun<CourtPresence>> stints;

  const PlayerPresence({required this.tagId, required this.stints});

  factory PlayerPresence.empty(String tagId) =>
      PlayerPresence(tagId: tagId, stints: const []);

  /// Segments one tag's time-ordered track.
  factory PlayerPresence.fromTrack(
    String tagId,
    List<PositionSample> track, {
    required Court court,
    PlayThresholds thresholds = PlayThresholds.defaults,
  }) {
    if (track.isEmpty) return PlayerPresence.empty(tagId);

    // The starting state is read with the *leaving* rule rather than the
    // entering one: a recording that begins with a player already standing on
    // the sideline should open with them playing, which is overwhelmingly what
    // it means, and only a tag clearly beyond the lines starts on the bench.
    var state = _isOutside(track.first, court, thresholds.offCourtMarginMeters)
        ? CourtPresence.bench
        : CourtPresence.onCourt;

    final states = <CourtPresence>[];
    for (final sample in track) {
      state = switch (state) {
        CourtPresence.onCourt =>
          _isOutside(sample, court, thresholds.offCourtMarginMeters)
              ? CourtPresence.bench
              : CourtPresence.onCourt,
        CourtPresence.bench =>
          _isOutside(sample, court, -thresholds.onCourtInsetMeters)
              ? CourtPresence.bench
              : CourtPresence.onCourt,
      };
      states.add(state);
    }

    return PlayerPresence(
      tagId: tagId,
      stints: buildRuns<CourtPresence>(
        length: track.length,
        valueAt: (i) => states[i],
        timeAt: (i) => track[i].timestampMicros,
        endMicros: track.last.timestampMicros,
        minDuration: thresholds.minStint,
      ),
    );
  }

  /// Whether ([PositionSample.x], [PositionSample.y]) lies beyond the playing
  /// lines by more than [margin] metres.
  ///
  /// A negative [margin] shrinks the court instead of growing it, which is how
  /// the entering rule is expressed: "outside the court inset by 10 cm" is the
  /// same test as "not far enough inside to count as having come on".
  static bool _isOutside(PositionSample sample, Court court, double margin) =>
      sample.x < -margin ||
      sample.x > court.widthMeters + margin ||
      sample.y < -margin ||
      sample.y > court.heightMeters + margin;

  List<TimedRun<CourtPresence>> get onCourtStints =>
      [for (final s in stints) if (s.value == CourtPresence.onCourt) s];

  List<TimedRun<CourtPresence>> get benchStints =>
      [for (final s in stints) if (s.value == CourtPresence.bench) s];

  Duration durationOf(CourtPresence presence) => Duration(
        microseconds: stints.fold(
          0,
          (sum, s) => s.value == presence ? sum + s.durationMicros : sum,
        ),
      );

  Duration get onCourtDuration => durationOf(CourtPresence.onCourt);

  Duration get benchDuration => durationOf(CourtPresence.bench);

  /// The span this tag reported over, on court and off it together.
  Duration get trackedDuration => stints.isEmpty
      ? Duration.zero
      : Duration(
          microseconds: stints.last.endMicros - stints.first.startMicros,
        );

  /// How many separate times this player came on.
  ///
  /// A player who started and was never substituted has one stint; the count
  /// is one more than the number of times they were brought back on.
  int get stintCount => onCourtStints.length;

  bool get everOnCourt => stintCount > 0;

  /// Share of the tracked span spent playing, in 0..1.
  ///
  /// Against the tag's own tracked span rather than the session's, because a
  /// tag that only started reporting halfway through was not on the bench for
  /// the first half — it was not measured. Callers wanting the share of the
  /// *session* should divide by the session duration themselves, which is a
  /// different and equally legitimate question.
  double get onCourtShare {
    final total = trackedDuration.inMicroseconds;
    return total <= 0 ? 0 : onCourtDuration.inMicroseconds / total;
  }

  /// The state in force at [micros]; null before the first stint or after the
  /// last, where nothing was measured.
  CourtPresence? presenceAt(int micros) {
    var low = 0;
    var high = stints.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final stint = stints[mid];
      if (micros < stint.startMicros) {
        high = mid - 1;
      } else if (micros >= stint.endMicros) {
        low = mid + 1;
      } else {
        return stint.value;
      }
    }
    // The final instant closes the last stint rather than opening a new one.
    if (stints.isNotEmpty && micros == stints.last.endMicros) {
      return stints.last.value;
    }
    return null;
  }

  bool isOnCourtAt(int micros) => presenceAt(micros) == CourtPresence.onCourt;

  @override
  String toString() => 'PlayerPresence($tagId, $stintCount stints, '
      '${onCourtDuration.inSeconds} s on court)';
}

/// Every tag's on-court and bench time for one recording.
///
/// Built against the session's **own** court, so a recording is always
/// segmented on the geometry it was captured with: widening a court in setup
/// months later cannot retroactively bring a substitute onto the floor.
@immutable
class SessionPresence {
  final Map<String, PlayerPresence> byTagId;
  final Court court;
  final PlayThresholds thresholds;

  const SessionPresence({
    required this.byTagId,
    required this.court,
    this.thresholds = PlayThresholds.defaults,
  });

  factory SessionPresence.fromTracks(
    Map<String, List<PositionSample>> tracks, {
    required Court court,
    PlayThresholds thresholds = PlayThresholds.defaults,
  }) =>
      SessionPresence(
        byTagId: {
          for (final entry in tracks.entries)
            entry.key: PlayerPresence.fromTrack(
              entry.key,
              entry.value,
              court: court,
              thresholds: thresholds,
            ),
        },
        court: court,
        thresholds: thresholds,
      );

  /// The presence of [tagId], or an empty one for a tag that reported nothing.
  PlayerPresence forTag(String tagId) =>
      byTagId[tagId] ?? PlayerPresence.empty(tagId);

  bool get isEmpty => byTagId.isEmpty;

  /// Whether anybody was ever off the playing surface.
  ///
  /// False for a recording with no substitutions in it, which is worth knowing
  /// before offering a reader a bench figure that is zero for everyone.
  bool get hasBenchTime =>
      byTagId.values.any((p) => p.benchDuration > Duration.zero);
}
