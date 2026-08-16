import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/play_metrics.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/sessions/analysis_widgets.dart';
import 'package:kinetag/src/features/sessions/sessions_screen.dart';
import 'package:kinetag/src/storage/storage_providers.dart';

import '../support/fake_session_repository.dart';

late ProviderContainer container;
late FakeSessionRepository repository;

const int _startMicros = 1786000000000000;
const int _stepMicros = 100000; // 10 Hz
const double _seconds = 120;
const double _periodSeconds = 30;

/// A session with two goalkeepers who leave their line while their own team
/// attacks, and one field player who spends the middle of it on the bench.
///
/// Everything the report needs to exercise both halves of the segmentation:
/// a phase to infer, and a substitution to find.
Future<Session> seedMatch(FakeSessionRepository repository) async {
  final court = Court.handball();

  final players = [
    const Player(
      id: 'p-gk-home',
      name: 'Home Keeper',
      number: 1,
      team: 'Home',
      side: TeamSide.home,
      role: PlayerRole.goalkeeper,
    ),
    const Player(
      id: 'p-gk-away',
      name: 'Away Keeper',
      number: 12,
      team: 'Away',
      side: TeamSide.away,
      role: PlayerRole.goalkeeper,
    ),
    const Player(
      id: 'p-sub',
      name: 'Rotating Back',
      number: 7,
      team: 'Home',
      side: TeamSide.home,
      role: PlayerRole.leftBack,
    ),
  ];

  final tagIds = ['tag-gk-home', 'tag-gk-away', 'tag-sub'];

  final session = Session(
    id: 'match-1',
    name: 'Tuesday',
    createdAt: DateTime.fromMicrosecondsSinceEpoch(_startMicros, isUtc: true),
    court: court,
    teams: [
      for (final side in TeamSide.values)
        Team(
          side: side,
          name: side.displayName,
          colorValue: Team.colorPalette[side.index],
        ),
    ],
    tags: [
      for (final id in tagIds) Tag(id: id, hardwareId: id, name: id),
    ],
    players: players,
    tagAssignments: [
      for (var i = 0; i < tagIds.length; i++)
        TagAssignment(
          id: 'a-$i',
          playerId: players[i].id,
          tagId: tagIds[i],
        ),
    ],
    status: SessionStatus.completed,
    startedAt: DateTime.fromMicrosecondsSinceEpoch(_startMicros, isUtc: true),
    stoppedAt: DateTime.fromMicrosecondsSinceEpoch(
      _startMicros + (_seconds * 1e6).round(),
      isUtc: true,
    ),
  );

  final samples = <PositionSample>[];
  final count = (_seconds * 1e6 / _stepMicros).round() + 1;

  for (var i = 0; i < count; i++) {
    final t = i * _stepMicros / 1e6;
    final at = _startMicros + i * _stepMicros;
    final phase = math.sin(2 * math.pi * t / _periodSeconds);

    void add(String tagId, double x, double y) => samples.add(
          PositionSample(timestampMicros: at, tagId: tagId, x: x, y: y),
        );

    // Each keeper advances up the court while their own team attacks.
    add('tag-gk-home', 2.0 + 1.3 * phase, 10);
    add('tag-gk-away', court.widthMeters - (2.0 - 1.3 * phase), 10);

    // On court, off from 60 s to 100 s, back on for the last twenty seconds.
    final benched = t >= 60 && t < 100;
    add('tag-sub', benched ? 20.0 : 10 + 8 * (1 + phase) / 2, benched ? -0.5 : 8);
  }

  await repository.saveSession(session.copyWith(sampleCount: samples.length));
  await repository.appendSamples(session.id, samples);
  return session;
}

/// Opens the seeded session's team analysis page.
Future<void> pumpAnalysis(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SessionsScreen())),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tuesday'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Analysis'));
  await tester.pumpAndSettle();
}

/// The value shown on the tile labelled [label].
String tileValue(WidgetTester tester, String label) => tester
    .widget<StatTile>(
      find.byWidgetPredicate((w) => w is StatTile && w.label == label),
    )
    .value;

Future<void> selectSplit(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(SegmentedButton<PlaySplit>),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    repository = FakeSessionRepository();
    container = ProviderContainer(
      overrides: [sessionRepositoryProvider.overrideWith((ref) => repository)],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('reports game time in absolute and relative terms',
      (tester) async {
    await seedMatch(repository);
    await pumpAnalysis(tester);

    expect(find.text('Game time'), findsOneWidget);
    expect(tileValue(tester, 'Session length'), '02:00');
    // Forty seconds off, found from the tag's position alone.
    expect(tileValue(tester, 'Bench time'), '00:40');
    expect(tileValue(tester, 'Substitutions'), '1');
  });

  testWidgets('the report defaults to playing time, not the whole recording',
      (tester) async {
    await seedMatch(repository);
    await pumpAnalysis(tester);

    expect(find.text('Totals — on court'), findsOneWidget);
    expect(
      find.textContaining('Bench time excluded'),
      findsOneWidget,
      reason: 'the reader is told what is being measured',
    );
  });

  testWidgets('choosing a phase re-scopes every figure on the page',
      (tester) async {
    await seedMatch(repository);
    await pumpAnalysis(tester);

    final playing = tileValue(tester, 'Measured');
    final playingDistance = tileValue(tester, 'Total distance');

    await selectSplit(tester, 'Attacking');

    expect(find.text('Totals — attacking'), findsOneWidget);
    expect(
      tileValue(tester, 'Measured'),
      isNot(playing),
      reason: 'attacking covers less time than the whole of playing time',
    );
    expect(tileValue(tester, 'Total distance'), isNot(playingDistance));

    await selectSplit(tester, 'Defending');
    expect(find.text('Totals — defending'), findsOneWidget);
  });

  testWidgets('the ranking table names the split it is measuring',
      (tester) async {
    await seedMatch(repository);
    await pumpAnalysis(tester);

    await tester.scrollUntilVisible(find.byType(DataTable), 200);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('On court'),
      ),
      findsOneWidget,
      reason: 'the time column is labelled with the split',
    );
    expect(
      find.descendant(
        of: find.byType(DataTable),
        matching: find.text('Of session'),
      ),
      findsOneWidget,
      reason: 'and carries the relative reading beside it',
    );
  });

  testWidgets('a player page reports their own time and phase split',
      (tester) async {
    await seedMatch(repository);
    await pumpAnalysis(tester);

    await tester.scrollUntilVisible(find.byType(DataTable), 200);
    final row = find.descendant(
      of: find.byType(DataTable),
      matching: find.text('Rotating Back'),
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Time on court'), 200);
    await tester.pumpAndSettle();

    // Eighty of the hundred and twenty seconds, both ways round.
    expect(tileValue(tester, 'Played'), '01:20');
    expect(find.textContaining('67% of the 02:00 session'), findsOneWidget);
    expect(tileValue(tester, 'On the bench'), '00:40');
    expect(tileValue(tester, 'Stints'), '2');

    await tester.scrollUntilVisible(find.text('Attack and defence'), 200);
    await tester.pumpAndSettle();
    expect(find.text('ATTACKING'), findsOneWidget);
    expect(find.text('DEFENDING'), findsOneWidget);
  });

  testWidgets('a session with no goalkeeper says so instead of guessing',
      (tester) async {
    await seedMatch(repository);
    // Strip the roles, leaving the same trajectories with nothing to read the
    // phase from.
    final stored = (await repository.listSessions()).single;
    await repository.saveSession(
      stored.copyWith(
        players: [
          for (final player in stored.players) player.copyWith(clearRole: true),
        ],
      ),
    );

    await pumpAnalysis(tester);

    expect(
      find.textContaining('no tracked goalkeeper'),
      findsOneWidget,
      reason: 'the reason is named, not hidden',
    );

    final attacking = tester.widget<SegmentedButton<PlaySplit>>(
      find.byType(SegmentedButton<PlaySplit>),
    );
    expect(
      attacking.segments
          .firstWhere((s) => s.value == PlaySplit.attacking)
          .enabled,
      isFalse,
      reason: 'offered but not selectable, so the reader learns what it needs',
    );
  });
}
