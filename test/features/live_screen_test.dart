import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/live/live_controller.dart';
import 'package:kinetag/src/features/live/live_screen.dart';
import 'package:kinetag/src/recording/recording_providers.dart';
import 'package:kinetag/src/recording/recording_sink.dart';
import 'package:kinetag/src/tracking/tracking_providers.dart';

import '../support/fake_tracking_source.dart';

late ProviderContainer container;
late FakeTrackingSource source;

Future<void> pumpLive(WidgetTester tester,
    {Size size = const Size(1400, 850)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  source = FakeTrackingSource();
  addTearDown(source.dispose);

  container = ProviderContainer(
    overrides: [
      trackingSourceProvider.overrideWith((ref) => source),
      recordingSinkProvider.overrideWith((ref) => InMemoryRecordingSink()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: LiveScreen())),
    ),
  );
  // The screen connects in a microtask, then status messages arrive.
  await tester.pump();
  await tester.pump();
}

LiveState get state => container.read(liveControllerProvider);

void main() {
  testWidgets('connects on open and shows the tracking status',
      (tester) async {
    await pumpLive(tester);

    expect(find.text('Live'), findsOneWidget);
    expect(find.byType(CourtCanvas), findsOneWidget);
    expect(source.connectCount, 1);
    expect(find.text('Tracking'), findsOneWidget);
  });

  testWidgets('reports the tags in the latest frame', (tester) async {
    await pumpLive(tester);

    source.emitFrame(testFrame(timestampMicros: 1000000, tagCount: 5));
    await tester.pump();

    expect(find.text('5 tags'), findsOneWidget);
  });

  testWidgets('shows elapsed time derived from frame timestamps',
      (tester) async {
    await pumpLive(tester);

    source.emitFrame(testFrame(timestampMicros: 4000000));
    source.emitFrame(testFrame(timestampMicros: 66000000));
    await tester.pump();

    // 62 s between the first and last frame.
    expect(find.text('01:02'), findsOneWidget);
  });

  testWidgets('starts and stops a recording', (tester) async {
    await pumpLive(tester);

    await tester.tap(find.text('Start recording'));
    await tester.pump();

    expect(state.isRecording, isTrue);
    expect(find.text('Stop recording'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);

    source.emitFrame(testFrame(timestampMicros: 1000000, tagCount: 3));
    await tester.pump();
    expect(find.text('3 samples'), findsOneWidget);

    await tester.tap(find.text('Stop recording'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.isRecording, isFalse);
    expect(find.text('Start recording'), findsOneWidget);
    expect(find.textContaining('3 samples'), findsWidgets);
  });

  testWidgets('recording is unavailable while offline', (tester) async {
    await pumpLive(tester);

    await tester.tap(find.text('Stop tracking'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Start tracking'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
      reason: 'cannot record without a connected source',
    );
  });

  testWidgets('surfaces a source error', (tester) async {
    await pumpLive(tester);

    source.emitError('hub unreachable');
    await tester.pump();

    expect(find.text('hub unreachable'), findsOneWidget);
  });

  testWidgets('lays out on a phone-width window without overflowing',
      (tester) async {
    await pumpLive(tester, size: const Size(420, 780));

    source.emitFrame(testFrame(timestampMicros: 1000000));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CourtCanvas), findsOneWidget);
  });
}
