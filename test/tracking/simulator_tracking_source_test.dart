import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/tracking/simulator/simulator_tracking_source.dart';
import 'package:kinetag/src/tracking/tracking_message.dart';

extension on Stream<TrackingMessage> {
  /// Narrows the sealed message stream to one variant.
  Stream<T> ofType<T extends TrackingMessage>() =>
      where((m) => m is T).cast<T>();
}

/// A source running far faster than real time, so tests finish quickly. The
/// simulation itself is driven by the nominal frame period, not by the wall
/// clock, so the fast rate does not change the data's meaning.
SimulatorTrackingSource makeSource({
  int sampleRateHz = 500,
  DateTime? startedAt,
}) {
  final source = SimulatorTrackingSource(
    court: Court.handball(),
    sampleRateHz: sampleRateHz,
    clock: startedAt == null ? null : () => startedAt,
  );
  addTearDown(source.dispose);
  return source;
}

void main() {
  group('lifecycle', () {
    test('starts disconnected', () {
      expect(makeSource().status, TrackingSourceStatus.disconnected);
    });

    test('announces connecting then connected', () async {
      final source = makeSource();
      final statuses = source.messages
          .ofType<TrackingStatusMessage>()
          .map((m) => m.status)
          .take(2)
          .toList();

      await source.connect();

      expect(await statuses, [
        TrackingSourceStatus.connecting,
        TrackingSourceStatus.connected,
      ]);
      expect(source.status, TrackingSourceStatus.connected);
    });

    test('connecting twice does not restart the stream', () async {
      final source = makeSource();
      await source.connect();
      final received = <TrackingMessage>[];
      final subscription = source.messages.listen(received.add);
      addTearDown(subscription.cancel);

      await source.connect();

      expect(
        received.whereType<TrackingStatusMessage>(),
        isEmpty,
        reason: 'a redundant connect must be a no-op',
      );
    });

    test('disconnect stops frames and is idempotent', () async {
      final source = makeSource();
      await source.connect();
      await source.messages.ofType<PositionFrameMessage>().first;

      await source.disconnect();
      expect(source.status, TrackingSourceStatus.disconnected);

      final after = <TrackingMessage>[];
      final subscription = source.messages.listen(after.add);
      addTearDown(subscription.cancel);
      await source.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(after, isEmpty);
    });

    test('dispose closes the stream and refuses reconnection', () async {
      final source = SimulatorTrackingSource(
        court: Court.handball(),
        sampleRateHz: 500,
      );
      await source.connect();
      final done = source.messages.drain<void>();

      await source.dispose();

      await done; // Completes only if the stream closed.
      expect(source.connect, throwsStateError);
    });
  });

  group('emission', () {
    test('emits frames carrying the whole squad', () async {
      final source = makeSource();
      final frames =
          source.messages.ofType<PositionFrameMessage>().take(5).toList();

      await source.connect();
      final received = await frames;

      expect(received, hasLength(5));
      for (final message in received) {
        expect(message.frame.samples, hasLength(12));
      }
    });

    test('stamps frames at exactly the nominal period', () async {
      // Timestamps must be regular: deriving them from the wall clock would
      // fold timer jitter into every derived velocity.
      final start = DateTime.utc(2026, 8, 16, 10);
      final source = makeSource(startedAt: start);
      final frames =
          source.messages.ofType<PositionFrameMessage>().take(4).toList();

      await source.connect();
      final received = await frames;

      for (var i = 0; i < received.length; i++) {
        expect(
          received[i].frame.timestampMicros,
          start.microsecondsSinceEpoch + (i + 1) * source.framePeriodMicros,
        );
      }
    });

    test('message timestamps agree with their frame', () async {
      final source = makeSource();
      final first = source.messages.ofType<PositionFrameMessage>().first;
      await source.connect();

      final message = await first;
      expect(message.timestampMicros, message.frame.timestampMicros);
    });

    test('sequence numbers increase by one across all message kinds',
        () async {
      final source = makeSource();
      final messages = source.messages.take(6).toList();

      await source.connect();
      final received = await messages;

      expect(
        received.map((m) => m.sequenceNumber),
        List.generate(received.length, (i) => i),
      );
    });

    test('reconnecting restarts sequence numbers at zero', () async {
      final source = makeSource();
      await source.connect();
      await source.messages.ofType<PositionFrameMessage>().take(3).toList();
      await source.disconnect();

      final afterReconnect = source.messages.take(1).toList();
      await source.connect();

      expect((await afterReconnect).single.sequenceNumber, 0);
    });

    test('is a broadcast source: two consumers see the same frames', () async {
      // The live view and the recorder subscribe at the same time.
      final source = makeSource();
      final a = source.messages.ofType<PositionFrameMessage>().take(3);
      final b = source.messages.ofType<PositionFrameMessage>().take(3);
      final both = Future.wait([a.toList(), b.toList()]);

      await source.connect();
      final results = await both;

      expect(
        results[0].map((m) => m.frame.timestampMicros),
        results[1].map((m) => m.frame.timestampMicros),
      );
    });
  });

  test('frame period follows the configured sample rate', () {
    expect(makeSource(sampleRateHz: 20).framePeriodMicros, 50000);
    expect(makeSource(sampleRateHz: 100).framePeriodMicros, 10000);
  });
}
