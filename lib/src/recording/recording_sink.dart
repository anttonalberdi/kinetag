import '../domain/domain.dart';

/// Where frames go while a session is being recorded.
///
/// The live view drives this interface and knows nothing about how — or
/// whether — frames reach disk. Phase 7 swaps [InMemoryRecordingSink] for a
/// SQLite-backed sink that batches writes, and no screen changes.
///
/// [add] is deliberately synchronous and non-blocking: it is called from the
/// tracking stream at up to 100 Hz per tag, so an implementation must buffer
/// and flush on its own schedule rather than awaiting a write per frame.
abstract class RecordingSink {
  bool get isRecording;

  /// Samples accepted since [begin].
  int get sampleCount;

  /// Opens a recording for [session], which must already carry its frozen
  /// setup snapshot.
  Future<void> begin(Session session);

  /// Accepts one frame. Ignored when no recording is open, so a frame that
  /// arrives in the same tick as a stop is never a crash.
  void add(PositionFrame frame);

  /// Closes the recording and returns the completed session, with its
  /// stop time and final sample count filled in.
  Future<Session> finish();
}

/// Keeps a recording in memory.
///
/// A stopgap until Phase 7: it makes the live view's Start/Stop controls
/// meaningful and gives the recording path a test double, but it holds every
/// frame in RAM (roughly 25 kB/s for twelve tags at 20 Hz), so it is not a
/// long-recording solution and is never the default once SQLite lands.
class InMemoryRecordingSink implements RecordingSink {
  final DateTime Function() _clock;

  Session? _session;
  int _sampleCount = 0;
  List<PositionFrame> _frames = [];

  /// Completed recordings, newest key last, kept for replay before storage
  /// exists.
  final Map<String, List<PositionFrame>> _completed = {};

  InMemoryRecordingSink({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  @override
  bool get isRecording => _session != null;

  @override
  int get sampleCount => _sampleCount;

  /// Frames buffered for the recording currently in progress.
  List<PositionFrame> get pendingFrames => List.unmodifiable(_frames);

  /// Frames stored for a finished session, or an empty list if unknown.
  List<PositionFrame> framesFor(String sessionId) =>
      List.unmodifiable(_completed[sessionId] ?? const <PositionFrame>[]);

  @override
  Future<void> begin(Session session) async {
    if (_session != null) {
      throw StateError('A recording is already in progress');
    }
    _session = session;
    _sampleCount = 0;
    _frames = [];
  }

  @override
  void add(PositionFrame frame) {
    if (_session == null) return;
    _frames.add(frame);
    _sampleCount += frame.samples.length;
  }

  @override
  Future<Session> finish() async {
    final session = _session;
    if (session == null) {
      throw StateError('finish() called with no recording in progress');
    }

    _completed[session.id] = _frames;
    _session = null;
    _frames = [];

    return session.copyWith(
      status: SessionStatus.completed,
      stoppedAt: _clock().toUtc(),
      sampleCount: _sampleCount,
    );
  }
}
