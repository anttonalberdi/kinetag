import 'dart:async';

import '../domain/domain.dart';
import '../storage/session_repository.dart';
import 'recording_sink.dart';

/// A [RecordingSink] that batches frames into a [SessionRepository].
///
/// ## Why buffering is not optional
///
/// [add] is called from the tracking stream — 20 Hz today, up to 30 tags at
/// 100 Hz eventually, which is 3000 samples a second. Writing each sample as
/// it arrives would put one transaction (and one disk sync) per sample on the
/// UI isolate and stall the frame the operator is watching. Samples are
/// therefore accumulated and written in batches, either when
/// [flushThresholdSamples] have piled up or every [flushInterval], whichever
/// comes first — the interval exists so that a quiet recording still reaches
/// disk promptly rather than sitting in RAM until the buffer happens to fill.
///
/// Writes are chained onto a single future so that batches land in order and
/// never overlap; a slow disk therefore lengthens the queue instead of
/// interleaving transactions.
class BufferedRecordingSink implements RecordingSink {
  final SessionRepository repository;

  /// Flush once this many samples are buffered.
  final int flushThresholdSamples;

  /// Flush at least this often while recording.
  final Duration flushInterval;

  final DateTime Function() _clock;

  Session? _session;
  List<PositionSample> _pending = [];
  int _acceptedCount = 0;

  Timer? _timer;
  Future<void> _writes = Future.value();
  Object? _lastWriteError;

  BufferedRecordingSink({
    required this.repository,
    this.flushThresholdSamples = 240,
    this.flushInterval = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  @override
  bool get isRecording => _session != null;

  @override
  int get sampleCount => _acceptedCount;

  @override
  Object? get lastWriteError => _lastWriteError;

  /// Samples accepted but not yet written to storage.
  int get pendingSampleCount => _pending.length;

  @override
  Future<void> begin(Session session) async {
    if (_session != null) {
      throw StateError('A recording is already in progress');
    }

    _session = session;
    _pending = [];
    _acceptedCount = 0;
    _lastWriteError = null;

    await repository.saveSession(session);
    _timer = Timer.periodic(flushInterval, (_) => _scheduleFlush());
  }

  @override
  void add(PositionFrame frame) {
    if (_session == null) return;

    _pending.addAll(frame.samples);
    _acceptedCount += frame.samples.length;

    if (_pending.length >= flushThresholdSamples) _scheduleFlush();
  }

  @override
  Future<Session> finish() async {
    final session = _session;
    if (session == null) {
      throw StateError('finish() called with no recording in progress');
    }

    _timer?.cancel();
    _timer = null;

    _scheduleFlush();
    await _writes;

    _session = null;

    // The stored count comes from the database, not from what was handed to
    // this sink: if a batch failed, the session must say what actually
    // survived rather than what was hoped for.
    final storedCount = await repository.countSamples(session.id);
    final completed = session.copyWith(
      status: SessionStatus.completed,
      stoppedAt: _clock().toUtc(),
      sampleCount: storedCount,
    );
    await repository.saveSession(completed);

    return completed;
  }

  /// Cancels the flush timer. Any in-flight write is left to complete.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _writes;
  }

  void _scheduleFlush() {
    if (_pending.isEmpty) return;

    final batch = _pending;
    _pending = [];
    final sessionId = _session?.id;
    if (sessionId == null) return;

    _writes = _writes.then((_) async {
      try {
        await repository.appendSamples(sessionId, batch);
      } catch (error) {
        // Keep the recording running: losing one batch is bad, tearing down
        // the capture mid-session is worse. The failure is surfaced through
        // [lastWriteError] and, on stop, through the session's real count.
        _lastWriteError = error;
      }
    });
  }
}
