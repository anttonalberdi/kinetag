import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/live/live_controller.dart';
import 'package:kinetag/src/features/setup/setup_state.dart';
import 'package:kinetag/src/recording/recording_providers.dart';
import 'package:kinetag/src/recording/recording_sink.dart';
import 'package:kinetag/src/tracking/tracking_message.dart';
import 'package:kinetag/src/tracking/tracking_providers.dart';

import '../support/fake_tracking_source.dart';

typedef LiveHarness = ({
  ProviderContainer container,
  FakeTrackingSource source,
  InMemoryRecordingSink sink,
});

LiveHarness makeHarness() {
  final source = FakeTrackingSource();
  final sink = InMemoryRecordingSink(
    clock: () => DateTime.utc(2026, 8, 16, 12, 30),
  );

  final container = ProviderContainer(
    overrides: [
      trackingSourceProvider.overrideWith((ref) => source),
      recordingSinkProvider.overrideWith((ref) => sink),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(source.dispose);

  // Instantiate the controller so it subscribes to the source.
  container.read(liveControllerProvider);

  return (container: container, source: source, sink: sink);
}

LiveState stateOf(ProviderContainer c) => c.read(liveControllerProvider);
LiveController controllerOf(ProviderContainer c) =>
    c.read(liveControllerProvider.notifier);

/// Lets queued stream events reach the controller.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('tracking status', () {
    test('starts from the source and follows status messages', () async {
      final h = makeHarness();
      expect(stateOf(h.container).status, TrackingSourceStatus.disconnected);

      await controllerOf(h.container).start();
      await settle();

      expect(stateOf(h.container).status, TrackingSourceStatus.connected);
      expect(stateOf(h.container).isConnected, isTrue);
    });

    test('surfaces errors and clears them on reconnect', () async {
      final h = makeHarness();
      h.source.emitError('hub unreachable');
      await settle();
      expect(stateOf(h.container).errorMessage, 'hub unreachable');

      await controllerOf(h.container).start();
      await settle();
      expect(stateOf(h.container).errorMessage, isNull);
    });

    test('accumulates dropped messages reported by the source', () async {
      final h = makeHarness();

      h.source.emitGap(lastSequence: 10, resumedSequence: 14);
      h.source.emitGap(lastSequence: 20, resumedSequence: 22);
      await settle();

      expect(stateOf(h.container).droppedMessages, 4);
    });

    test('a new connection resets the live clock', () async {
      final h = makeHarness();
      await controllerOf(h.container).start();
      h.source.emitFrame(testFrame(timestampMicros: 1000000));
      h.source.emitFrame(testFrame(timestampMicros: 3000000));
      await settle();
      expect(stateOf(h.container).liveElapsed, const Duration(seconds: 2));

      await controllerOf(h.container).start();
      await settle();

      expect(stateOf(h.container).liveElapsed, Duration.zero);
      expect(stateOf(h.container).framesReceived, 0);
    });
  });

  group('frames', () {
    test('expose the latest frame and the tag count', () async {
      final h = makeHarness();

      h.source.emitFrame(testFrame(timestampMicros: 500, tagCount: 4));
      await settle();

      final state = stateOf(h.container);
      expect(state.latestFrame!.timestampMicros, 500);
      expect(state.trackedTagCount, 4);
      expect(state.framesReceived, 1);
    });

    test('measure elapsed time from frame timestamps, not the wall clock',
        () async {
      // The displayed clock must describe the data, so that a stalled
      // pipeline shows a stalled clock instead of drifting on happily.
      final h = makeHarness();

      h.source.emitFrame(testFrame(timestampMicros: 10000000));
      h.source.emitFrame(testFrame(timestampMicros: 11500000));
      await settle();

      expect(stateOf(h.container).liveElapsed,
          const Duration(milliseconds: 1500));
    });

    test('are not recorded while no recording is open', () async {
      final h = makeHarness();

      h.source.emitFrame(testFrame(timestampMicros: 1000));
      await settle();

      expect(h.sink.isRecording, isFalse);
      expect(h.sink.sampleCount, 0);
      expect(stateOf(h.container).recordedSampleCount, 0);
    });
  });

  group('recording', () {
    test('writes frames to the sink and counts samples', () async {
      final h = makeHarness();
      await controllerOf(h.container).startRecording();

      h.source.emitFrame(testFrame(timestampMicros: 1000000, tagCount: 3));
      h.source.emitFrame(testFrame(timestampMicros: 1050000, tagCount: 3));
      await settle();

      expect(h.sink.sampleCount, 6);
      expect(stateOf(h.container).recordedSampleCount, 6);
    });

    test('elapsed time runs from the first recorded frame', () async {
      final h = makeHarness();
      h.source.emitFrame(testFrame(timestampMicros: 1000000));
      await settle();

      await controllerOf(h.container).startRecording();
      h.source.emitFrame(testFrame(timestampMicros: 2000000));
      h.source.emitFrame(testFrame(timestampMicros: 5000000));
      await settle();

      expect(stateOf(h.container).recordingElapsed,
          const Duration(seconds: 3));
    });

    test('snapshots the setup by value', () async {
      // Decision 5: moving a receiver after the fact must not rewrite what a
      // recording means.
      final h = makeHarness();
      final setup = h.container.read(setupControllerProvider.notifier);
      final receiverId = h.container.read(setupControllerProvider).receivers.first.id;

      await controllerOf(h.container).startRecording();
      final recorded = stateOf(h.container).recordingSession!;
      final capturedX =
          recorded.receivers.firstWhere((r) => r.id == receiverId).x;

      setup.moveReceiver(receiverId, x: capturedX + 7);

      expect(
        recorded.receivers.firstWhere((r) => r.id == receiverId).x,
        capturedX,
      );
      expect(
        h.container.read(setupControllerProvider).receivers
            .firstWhere((r) => r.id == receiverId)
            .x,
        capturedX + 7,
      );
    });

    test('snapshots the roster so labels survive the session', () async {
      final h = makeHarness();
      await controllerOf(h.container).startRecording();

      final session = stateOf(h.container).recordingSession!;
      expect(session.teams, hasLength(2));
      expect(session.teamFor(TeamSide.home)!.name, 'Home');
      expect(session.players, hasLength(12));
      expect(session.tags, hasLength(12));
      expect(session.tagAssignments, hasLength(12));
      expect(session.playerForTag(session.tags.first.id), isNotNull);
      expect(session.status, SessionStatus.recording);
    });

    test('stopping completes the session with the sink’s sample count',
        () async {
      final h = makeHarness();
      await controllerOf(h.container).startRecording();
      h.source.emitFrame(testFrame(timestampMicros: 1000000, tagCount: 3));
      h.source.emitFrame(testFrame(timestampMicros: 1050000, tagCount: 3));
      await settle();

      final completed = await controllerOf(h.container).stopRecording();

      expect(completed!.status, SessionStatus.completed);
      expect(completed.sampleCount, 6);
      expect(completed.stoppedAt, DateTime.utc(2026, 8, 16, 12, 30));
      expect(stateOf(h.container).isRecording, isFalse);
      expect(stateOf(h.container).lastCompletedSession, completed);
    });

    test('keeps the recorded frames retrievable by session id', () async {
      final h = makeHarness();
      await controllerOf(h.container).startRecording();
      h.source.emitFrame(testFrame(timestampMicros: 1000000));
      await settle();

      final completed = await controllerOf(h.container).stopRecording();

      expect(h.sink.framesFor(completed!.id), hasLength(1));
    });

    test('starting twice is a no-op', () async {
      final h = makeHarness();
      await controllerOf(h.container).startRecording();
      final first = stateOf(h.container).recordingSession;

      await controllerOf(h.container).startRecording();

      expect(stateOf(h.container).recordingSession, same(first));
    });

    test('stopping without a recording returns null', () async {
      final h = makeHarness();
      expect(await controllerOf(h.container).stopRecording(), isNull);
    });

    test('stopping tracking closes an open recording first', () async {
      final h = makeHarness();
      await controllerOf(h.container).start();
      await controllerOf(h.container).startRecording();
      h.source.emitFrame(testFrame(timestampMicros: 1000000));
      await settle();

      await controllerOf(h.container).stop();
      await settle();

      expect(h.sink.isRecording, isFalse);
      expect(stateOf(h.container).isRecording, isFalse);
      expect(stateOf(h.container).lastCompletedSession, isNotNull);
      expect(h.source.disconnectCount, 1);
    });
  });
}
