import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/tracking/replay/recorded_session_tracking_source.dart';
import 'package:kinetag/src/tracking/tracking_message.dart';

/// Ten frames, 100 ms apart, starting at an arbitrary absolute instant so the
/// relative-time handling is genuinely exercised.
const int kFirstMicros = 1786000000000000;
const int kStepMicros = 100000;

List<PositionFrame> makeFrames({int count = 10}) => [
      for (var i = 0; i < count; i++)
        PositionFrame(
          timestampMicros: kFirstMicros + i * kStepMicros,
          samples: [
            PositionSample(
              timestampMicros: kFirstMicros + i * kStepMicros,
              tagId: 'tag-1',
              x: i.toDouble(),
              y: 10,
            ),
          ],
        ),
    ];

Session makeSession() => Session(
      id: 'session-1',
      name: 'Recorded',
      createdAt: DateTime.utc(2026, 8, 16),
      court: Court.handball(),
      status: SessionStatus.completed,
    );

RecordedSessionTrackingSource makeSource({
  List<PositionFrame>? frames,
  Duration tick = const Duration(milliseconds: 10),
}) {
  final source = RecordedSessionTrackingSource(
    session: makeSession(),
    frames: frames ?? makeFrames(),
    tickInterval: tick,
  );
  addTearDown(source.dispose);
  return source;
}

extension on Stream<TrackingMessage> {
  Stream<T> ofType<T extends TrackingMessage>() =>
      where((m) => m is T).cast<T>();
}

void main() {
  group('timeline', () {
    test('reports the recording length relative to its first frame', () {
      expect(makeSource().duration, const Duration(milliseconds: 900));
    });

    test('an empty recording has no duration and never plays', () async {
      final source = makeSource(frames: const []);
      await source.connect();
      source.play();

      expect(source.duration, Duration.zero);
      expect(source.isPlaying, isFalse);
      expect(source.currentFrame, isNull);
    });

    test('locates the frame in force at a position', () {
      final source = makeSource();

      expect(source.indexAt(Duration.zero), 0);
      // Between frames, the frame already in force still applies.
      expect(source.indexAt(const Duration(milliseconds: 250)), 2);
      expect(source.indexAt(const Duration(milliseconds: 300)), 3);
      expect(source.indexAt(const Duration(seconds: 99)), 9);
    });
  });

  group('connect', () {
    test('shows the first frame without playing', () async {
      final source = makeSource();
      final first = source.messages.ofType<PositionFrameMessage>().first;

      await source.connect();

      expect((await first).frame.timestampMicros, kFirstMicros);
      expect(source.status, TrackingSourceStatus.idle);
      expect(source.isPlaying, isFalse);
      expect(source.position, Duration.zero);
    });
  });

  group('seeking', () {
    test('works forwards and backwards', () async {
      final source = makeSource();
      await source.connect();

      source.seek(const Duration(milliseconds: 700));
      expect(source.currentFrame!.samples.single.x, 7);

      source.seek(const Duration(milliseconds: 200));
      expect(source.currentFrame!.samples.single.x, 2);
    });

    test('emits the frame at the new position', () async {
      final source = makeSource();
      await source.connect();
      final next = source.messages.ofType<PositionFrameMessage>().first;

      source.seek(const Duration(milliseconds: 500));

      expect((await next).frame.samples.single.x, 5);
    });

    test('clamps to the recording bounds', () async {
      final source = makeSource();
      await source.connect();

      source.seek(const Duration(seconds: -5));
      expect(source.position, Duration.zero);

      source.seek(const Duration(seconds: 5));
      expect(source.position, const Duration(milliseconds: 900));
    });

    test('does not re-emit a frame that is already showing', () async {
      final source = makeSource();
      await source.connect();

      final received = <PositionFrameMessage>[];
      final subscription =
          source.messages.ofType<PositionFrameMessage>().listen(received.add);
      addTearDown(subscription.cancel);

      // Both positions fall inside frame 3's interval.
      source.seek(const Duration(milliseconds: 300));
      source.seek(const Duration(milliseconds: 350));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
    });
  });

  group('playback', () {
    test('advances through the recording and stops at the end', () async {
      final source = makeSource(tick: const Duration(milliseconds: 5));
      await source.connect();
      final done = source.messages
          .ofType<PositionFrameMessage>()
          .firstWhere((m) => m.frame.samples.single.x == 9);

      source.play();
      expect(source.isPlaying, isTrue);
      await done;
      // The tick that reaches the end pauses playback.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(source.isPlaying, isFalse);
      expect(source.position, source.duration);
      expect(source.status, TrackingSourceStatus.idle);
    });

    test('playing from the end restarts from the beginning', () async {
      final source = makeSource();
      await source.connect();
      source.seek(source.duration);

      source.play();

      expect(source.position, Duration.zero);
      source.pause();
    });

    test('speed scales how fast the playhead moves', () async {
      final slow = makeSource(tick: const Duration(milliseconds: 10));
      final fast = makeSource(tick: const Duration(milliseconds: 10));
      await slow.connect();
      await fast.connect();
      fast.playbackSpeed = 4.0;

      slow.play();
      fast.play();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      slow.pause();
      fast.pause();

      expect(fast.position, greaterThan(slow.position * 2));
    });

    test('pausing stops emission but keeps the playhead', () async {
      final source = makeSource(tick: const Duration(milliseconds: 5));
      await source.connect();
      source.play();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      source.pause();
      final resting = source.position;

      final received = <PositionFrameMessage>[];
      final subscription =
          source.messages.ofType<PositionFrameMessage>().listen(received.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(source.position, resting);
      expect(received, isEmpty);
      expect(source.status, TrackingSourceStatus.idle);
    });
  });

  test('behaves as a TrackingSource: disconnect then dispose', () async {
    final source = RecordedSessionTrackingSource(
      session: makeSession(),
      frames: makeFrames(),
    );
    await source.connect();
    source.play();

    await source.disconnect();
    expect(source.isPlaying, isFalse);
    expect(source.status, TrackingSourceStatus.disconnected);

    final closed = source.messages.drain<void>();
    await source.dispose();
    await closed;
    expect(source.connect, throwsStateError);
  });
}
