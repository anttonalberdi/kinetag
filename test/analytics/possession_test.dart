import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/court_presence.dart';
import 'package:kinetag/src/analytics/possession.dart';
import 'package:kinetag/src/domain/domain.dart';

const int kStartMicros = 1786000000000000;
const int kStepMicros = 50000; // 20 Hz
const double kPeriodSeconds = 30.0;

final Court court = Court.handball();

/// A session whose roster gives [roles] to one tag each, on alternating sides
/// unless the entry says otherwise.
Session sessionWith(Map<String, (PlayerRole?, TeamSide?)> roster) {
  final tagIds = roster.keys.toList();
  return Session(
    id: 'session-1',
    name: 'Test session',
    createdAt: DateTime.fromMicrosecondsSinceEpoch(kStartMicros, isUtc: true),
    court: court,
    tags: [for (final id in tagIds) Tag(id: id, hardwareId: id, name: id)],
    players: [
      for (final id in tagIds)
        Player(
          id: 'player-$id',
          name: 'Player $id',
          side: roster[id]!.$2,
          role: roster[id]!.$1,
        ),
    ],
    tagAssignments: [
      for (final id in tagIds)
        TagAssignment(id: 'a-$id', playerId: 'player-$id', tagId: id),
    ],
    status: SessionStatus.completed,
  );
}

/// Where play is at second [t], in -1..1: +1 with the home team attacking.
double phaseAt(double t) => math.sin(2 * math.pi * t / kPeriodSeconds);

/// A keeper who leaves their line by [swingMeters] while their team attacks.
///
/// [restMeters] is how far off the goal line they stand at neutral, which the
/// centring is supposed to make irrelevant — the tests below rely on that.
List<PositionSample> keeperTrack({
  required String tagId,
  required TeamSide side,
  double seconds = 120,
  double restMeters = 2.0,
  double swingMeters = 1.3,
}) {
  final count = (seconds * 1e6 / kStepMicros).round() + 1;
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = i * kStepMicros / 1e6;
        // Advance up the court from this keeper's own goal line, largest when
        // their own team is attacking.
        final own = side == TeamSide.home ? phaseAt(t) : -phaseAt(t);
        final advance = restMeters + swingMeters * own;
        return PositionSample(
          timestampMicros: kStartMicros + i * kStepMicros,
          tagId: tagId,
          x: side == TeamSide.home ? advance : court.widthMeters - advance,
          y: 10,
        );
      }(),
  ];
}

PossessionTimeline timelineFor(
  Map<String, List<PositionSample>> tracks,
  Session session,
) =>
    PossessionTimeline.fromKeepers(
      tracks: tracks,
      session: session,
      presence: SessionPresence.fromTracks(tracks, court: court),
    );

int at(double seconds) => kStartMicros + (seconds * 1e6).round();

void main() {
  group('inference', () {
    test('reads the attacking side off the two goalkeepers', () {
      final tracks = {
        'gk-home': keeperTrack(tagId: 'gk-home', side: TeamSide.home),
        'gk-away': keeperTrack(tagId: 'gk-away', side: TeamSide.away),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({
          'gk-home': (PlayerRole.goalkeeper, TeamSide.home),
          'gk-away': (PlayerRole.goalkeeper, TeamSide.away),
        }),
      );

      expect(timeline.isAvailable, isTrue);
      expect(timeline.keeperSides, {TeamSide.home, TeamSide.away});

      // A quarter period in, the home keeper is as far up the court as they
      // get and the away keeper is on their line.
      expect(timeline.attackingAt(at(7.5)), TeamSide.home);
      expect(timeline.attackingAt(at(22.5)), TeamSide.away);
      expect(timeline.attackingAt(at(37.5)), TeamSide.home);
    });

    test('a phase is the same fact seen from either side', () {
      final tracks = {
        'gk-home': keeperTrack(tagId: 'gk-home', side: TeamSide.home),
        'gk-away': keeperTrack(tagId: 'gk-away', side: TeamSide.away),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({
          'gk-home': (PlayerRole.goalkeeper, TeamSide.home),
          'gk-away': (PlayerRole.goalkeeper, TeamSide.away),
        }),
      );

      expect(timeline.phaseAt(at(7.5), TeamSide.home), PlayPhase.attacking);
      expect(timeline.phaseAt(at(7.5), TeamSide.away), PlayPhase.defending);
      expect(timeline.phaseAt(at(7.5), null), PlayPhase.unclear,
          reason: 'without a side there is no end to attack');
    });

    test('an even match splits the time between the two ends', () {
      final tracks = {
        'gk-home': keeperTrack(tagId: 'gk-home', side: TeamSide.home),
        'gk-away': keeperTrack(tagId: 'gk-away', side: TeamSide.away),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({
          'gk-home': (PlayerRole.goalkeeper, TeamSide.home),
          'gk-away': (PlayerRole.goalkeeper, TeamSide.away),
        }),
      );

      final attacking = timeline.teamTimeIn(TeamSide.home, PlayPhase.attacking);
      final defending = timeline.teamTimeIn(TeamSide.home, PlayPhase.defending);

      expect(attacking.inSeconds, closeTo(defending.inSeconds, 8));
      expect(
        attacking + defending +
            timeline.teamTimeIn(TeamSide.home, PlayPhase.unclear),
        timeline.measuredDuration,
        reason: 'the phases partition the measured span',
      );
    });

    test('one goalkeeper is enough', () {
      final tracks = {
        'gk-home': keeperTrack(tagId: 'gk-home', side: TeamSide.home),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({'gk-home': (PlayerRole.goalkeeper, TeamSide.home)}),
      );

      expect(timeline.keeperSides, {TeamSide.home});
      expect(timeline.attackingAt(at(7.5)), TeamSide.home);
      expect(timeline.attackingAt(at(22.5)), TeamSide.away);
    });

    test('a keeper who stands well off their line is not always attacking', () {
      // Six metres off the line all match, which the centring must remove: an
      // uncentred signal would read this keeper as permanently advanced.
      final tracks = {
        'gk-home': keeperTrack(
          tagId: 'gk-home',
          side: TeamSide.home,
          restMeters: 6.0,
        ),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({'gk-home': (PlayerRole.goalkeeper, TeamSide.home)}),
      );

      expect(
        timeline.teamTimeIn(TeamSide.home, PlayPhase.attacking).inSeconds,
        closeTo(
          timeline.teamTimeIn(TeamSide.home, PlayPhase.defending).inSeconds,
          8,
        ),
      );
    });

    test('a keeper who never leaves their line yields no phases', () {
      final tracks = {
        'gk-home': keeperTrack(
          tagId: 'gk-home',
          side: TeamSide.home,
          swingMeters: 0.0,
        ),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({'gk-home': (PlayerRole.goalkeeper, TeamSide.home)}),
      );

      expect(timeline.isAvailable, isFalse,
          reason: 'no signal must read as no answer, not as a guess');
    });
  });

  group('what it needs', () {
    test('a roster with no goalkeeper yields no timeline', () {
      final tracks = {
        'tag-1': keeperTrack(tagId: 'tag-1', side: TeamSide.home),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({'tag-1': (PlayerRole.pivot, TeamSide.home)}),
      );

      expect(timeline.isAvailable, isFalse);
      expect(timeline.keeperSides, isEmpty);
      expect(timeline.attackingAt(at(7.5)), isNull);
    });

    test('a goalkeeper with no side yields no timeline', () {
      final tracks = {
        'gk': keeperTrack(tagId: 'gk', side: TeamSide.home),
      };
      final timeline = timelineFor(
        tracks,
        sessionWith({'gk': (PlayerRole.goalkeeper, null)}),
      );

      expect(timeline.isAvailable, isFalse);
    });

    test('a benched goalkeeper says nothing about where play is', () {
      // The keeper's tag reports from a seat outside the sideline all match.
      final benched = [
        for (var i = 0; i < 2401; i++)
          PositionSample(
            timestampMicros: kStartMicros + i * kStepMicros,
            tagId: 'gk-home',
            x: 18,
            y: -0.5,
          ),
      ];
      final timeline = timelineFor(
        {'gk-home': benched},
        sessionWith({'gk-home': (PlayerRole.goalkeeper, TeamSide.home)}),
      );

      expect(timeline.isAvailable, isFalse);
    });
  });
}
