import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/recording/buffered_recording_sink.dart';
import 'package:kinetag/src/storage/session_repository.dart';

/// A repository that records what it was asked to do, so the batching
/// behaviour itself can be asserted rather than inferred from row counts.
class SpyRepository implements SessionRepository {
  final List<Session> saved = [];
  final List<List<PositionSample>> batches = [];
  final List<PositionSample> stored = [];

  /// When set, the next [appendSamples] throws it.
  Object? failNextAppend;

  @override
  Future<void> saveSession(Session session) async => saved.add(session);

  @override
  Future<void> appendSamples(
    String sessionId,
    List<PositionSample> samples,
  ) async {
    final failure = failNextAppend;
    if (failure != null) {
      failNextAppend = null;
      throw failure;
    }
    batches.add(samples);
    stored.addAll(samples);
  }

  @override
  Future<int> countSamples(String sessionId) async => stored.length;

  @override
  Future<Session?> findSession(String id) async =>
      saved.where((s) => s.id == id).lastOrNull;

  @override
  Future<List<Session>> listSessions() async => saved;

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<List<PositionSample>> samplesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  }) async =>
      stored;

  @override
  Future<List<PositionFrame>> framesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  }) async =>
      PositionFrame.groupByTimestamp(stored);

  @override
  Future<({int firstMicros, int lastMicros})?> timeRange(
          String sessionId) async =>
      stored.isEmpty
          ? null
          : (
              firstMicros: stored.first.timestampMicros,
              lastMicros: stored.last.timestampMicros
            );

  @override
  Future<void> close() async {}
}

Session makeSession() => Session(
      id: 'session-1',
      name: 'Training',
      createdAt: DateTime.utc(2026, 8, 16, 9),
      court: Court.handball(),
      status: SessionStatus.recording,
      startedAt: DateTime.utc(2026, 8, 16, 9),
    );

PositionFrame frameAt(int timestampMicros, {int tags = 4}) => PositionFrame(
      timestampMicros: timestampMicros,
      samples: [
        for (var i = 0; i < tags; i++)
          PositionSample(
            timestampMicros: timestampMicros,
            tagId: 'tag-$i',
            x: i.toDouble(),
            y: 1,
          ),
      ],
    );

void main() {
  test('buffers instead of writing a row per frame', () async {
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(
      repository: repository,
      flushThresholdSamples: 40,
      flushInterval: const Duration(hours: 1),
    );

    await sink.begin(makeSession());
    for (var i = 0; i < 5; i++) {
      sink.add(frameAt(i * 50000));
    }

    expect(repository.batches, isEmpty, reason: '20 samples is under the bar');
    expect(sink.pendingSampleCount, 20);
    expect(sink.sampleCount, 20);
  });

  test('flushes in one batch once the threshold is reached', () async {
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(
      repository: repository,
      flushThresholdSamples: 12,
      flushInterval: const Duration(hours: 1),
    );

    await sink.begin(makeSession());
    for (var i = 0; i < 3; i++) {
      sink.add(frameAt(i * 50000));
    }
    await sink.finish();

    expect(repository.batches, hasLength(1));
    expect(repository.batches.single, hasLength(12));
  });

  test('flushes on its interval when frames trickle in', () async {
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(
      repository: repository,
      flushThresholdSamples: 100000,
      flushInterval: const Duration(milliseconds: 20),
    );

    await sink.begin(makeSession());
    sink.add(frameAt(0));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(repository.stored, hasLength(4));
    await sink.finish();
  });

  test('writes everything still buffered when the recording stops', () async {
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(
      repository: repository,
      flushThresholdSamples: 100000,
      flushInterval: const Duration(hours: 1),
      clock: () => DateTime.utc(2026, 8, 16, 10, 30),
    );

    await sink.begin(makeSession());
    sink.add(frameAt(1000000));
    sink.add(frameAt(1050000));
    final completed = await sink.finish();

    expect(repository.stored, hasLength(8));
    expect(completed.status, SessionStatus.completed);
    expect(completed.sampleCount, 8);
    expect(completed.stoppedAt, DateTime.utc(2026, 8, 16, 10, 30));
    expect(sink.isRecording, isFalse);
  });

  test('saves the session before any sample is written', () async {
    // The foreign key from samples to sessions requires it, and a crash
    // mid-recording should still leave a session row behind.
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(repository: repository);

    await sink.begin(makeSession());

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.status, SessionStatus.recording);
    await sink.finish();
  });

  test('reports the count that actually reached storage', () async {
    // A failed batch must not be counted as recorded.
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(
      repository: repository,
      flushThresholdSamples: 4,
      flushInterval: const Duration(hours: 1),
    );

    await sink.begin(makeSession());
    repository.failNextAppend = Exception('disk full');
    sink.add(frameAt(1000000)); // 4 samples, flushed and lost
    await Future<void>.delayed(Duration.zero);
    sink.add(frameAt(1050000)); // 4 samples, flushed successfully

    final completed = await sink.finish();

    expect(sink.lastWriteError, isNotNull);
    expect(sink.sampleCount, 8, reason: 'accepted');
    expect(completed.sampleCount, 4, reason: 'actually stored');
  });

  test('keeps recording after a failed batch', () async {
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(
      repository: repository,
      flushThresholdSamples: 4,
      flushInterval: const Duration(hours: 1),
    );

    await sink.begin(makeSession());
    repository.failNextAppend = Exception('transient');
    sink.add(frameAt(1000000));
    await Future<void>.delayed(Duration.zero);

    expect(sink.isRecording, isTrue);

    sink.add(frameAt(1050000));
    await sink.finish();
    expect(repository.stored, hasLength(4));
  });

  test('ignores frames when no recording is open', () async {
    final repository = SpyRepository();
    final sink = BufferedRecordingSink(repository: repository);

    sink.add(frameAt(1000000));

    expect(sink.sampleCount, 0);
    expect(repository.stored, isEmpty);
  });

  test('refuses to begin twice or finish without a recording', () async {
    final sink = BufferedRecordingSink(repository: SpyRepository());

    expect(sink.finish, throwsStateError);
    await sink.begin(makeSession());
    expect(() => sink.begin(makeSession()), throwsStateError);
    await sink.finish();
  });
}
