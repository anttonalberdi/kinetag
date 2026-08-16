import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/sessions/replay_controller.dart';
import 'package:kinetag/src/features/sessions/sessions_screen.dart';
import 'package:kinetag/src/storage/storage_providers.dart';

import '../support/fake_session_repository.dart';
import '../support/session_fixtures.dart';

late ProviderContainer container;
late FakeSessionRepository repository;

Future<void> pumpSessions(WidgetTester tester,
    {Size size = const Size(1400, 850)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SessionsScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

ReplayState get replayState => container.read(replayControllerProvider);

void main() {
  setUp(() {
    repository = FakeSessionRepository();
    container = ProviderContainer(
      overrides: [sessionRepositoryProvider.overrideWith((ref) => repository)],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('invites a first recording when there is nothing stored',
      (tester) async {
    await pumpSessions(tester);

    expect(find.text('No recordings yet'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('lists stored recordings with their details', (tester) async {
    await seedRecording(repository, name: 'Tuesday drill', frameCount: 10);

    await pumpSessions(tester);

    expect(find.text('Tuesday drill'), findsOneWidget);
    expect(find.textContaining('20 samples'), findsOneWidget);
    expect(find.textContaining('2 players'), findsOneWidget);
  });

  testWidgets('opens a recording and replays it on the court',
      (tester) async {
    await seedRecording(repository, name: 'Tuesday drill');
    await pumpSessions(tester);

    await tester.tap(find.text('Tuesday drill'));
    await tester.pumpAndSettle();

    expect(find.byType(CourtCanvas), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('10 frames'), findsOneWidget);
    expect(replayState.frameCount, 10);
    // 00:00 of 00:00.9 — the timeline is scaled to the recording, not the
    // wall clock at capture time.
    expect(find.text('00:00'), findsWidgets);
  });

  testWidgets('scrubbing the timeline moves the playhead', (tester) async {
    await seedRecording(repository, name: 'Tuesday drill');
    await pumpSessions(tester);
    await tester.tap(find.text('Tuesday drill'));
    await tester.pumpAndSettle();

    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(slider.center.dx, slider.center.dy));
    await tester.pumpAndSettle();

    expect(replayState.position, greaterThan(Duration.zero));
    expect(replayState.frame!.sampleForTag('tag-0')!.x, greaterThan(0));

    // And back again: scrubbing must work in both directions.
    await tester.tapAt(Offset(slider.left + 4, slider.center.dy));
    await tester.pumpAndSettle();
    expect(replayState.position, Duration.zero);
  });

  testWidgets('play and pause drive the transport', (tester) async {
    await seedRecording(repository, name: 'Tuesday drill');
    await pumpSessions(tester);
    await tester.tap(find.text('Tuesday drill'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(replayState.isPlaying, isTrue);
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(replayState.isPlaying, isFalse);
  });

  testWidgets('going back closes the replay', (tester) async {
    await seedRecording(repository, name: 'Tuesday drill');
    await pumpSessions(tester);
    await tester.tap(find.text('Tuesday drill'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back to sessions'));
    await tester.pumpAndSettle();

    expect(find.text('Sessions'), findsOneWidget);
    expect(replayState.session, isNull);
  });

  testWidgets('deleting a recording asks first, then removes it',
      (tester) async {
    await seedRecording(repository, name: 'Tuesday drill');
    await pumpSessions(tester);

    await tester.tap(find.byTooltip('Delete recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Tuesday drill'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Tuesday drill'), findsNothing);
    expect(await repository.countSamples('session-1'), 0);
  });

  testWidgets('a recording with no samples cannot be opened', (tester) async {
    await seedRecording(repository, name: 'Empty run', frameCount: 0);
    await pumpSessions(tester);

    await tester.tap(find.text('Empty run'));
    await tester.pumpAndSettle();

    expect(find.text('Empty run'), findsOneWidget, reason: 'still the list');
    expect(find.byType(Slider), findsNothing);
  });
}
