import 'dart:async';

import '../../domain/domain.dart';
import '../tracking_message.dart';
import '../tracking_source.dart';

/// Plays a recorded session back through the [TrackingSource] interface.
///
/// Replay deliberately re-enters the app by the same door live tracking does:
/// the court canvas, the player layer and anything built on frames cannot
/// tell a recording from a hub. Only the transport controls — [play],
/// [pause], [seek], [playbackSpeed] — are extra, and only the replay screen
/// holds this concrete type.
///
/// ## Time model
///
/// Positions are expressed **relative to the first recorded frame**, so a
/// timeline starts at 00:00 regardless of when the session was captured,
/// while the frames themselves keep their absolute microsecond timestamps.
/// Playback advances that relative position by wall-clock ticks scaled by
/// [playbackSpeed] and then looks up the frame in force — rather than
/// stepping frame by frame — which is what makes 4× playback, a paused
/// scrub, and a recording with dropped frames all behave the same.
///
/// ## Loading
///
/// Frames are supplied ready-loaded. For prototype-length recordings the
/// replay controller reads them all up front; the repository's range queries
/// exist so that a windowed loader can be dropped in later without changing
/// anything here or above.
class RecordedSessionTrackingSource implements TrackingSource {
  final Session session;

  /// Frames in ascending time order.
  final List<PositionFrame> frames;

  /// Wall-clock interval between playback ticks. 60 Hz keeps the scrubber and
  /// the court smooth without out-running a 20 Hz recording.
  final Duration tickInterval;

  final StreamController<TrackingMessage> _controller =
      StreamController<TrackingMessage>.broadcast();

  int _sequence = 0;
  int _positionMicros = 0;
  int? _emittedIndex;
  double _playbackSpeed = 1.0;
  Timer? _timer;
  bool _disposed = false;
  TrackingSourceStatus _status = TrackingSourceStatus.disconnected;

  RecordedSessionTrackingSource({
    required this.session,
    required this.frames,
    this.tickInterval = const Duration(milliseconds: 16),
  });

  @override
  Stream<TrackingMessage> get messages => _controller.stream;

  @override
  TrackingSourceStatus get status => _status;

  bool get isPlaying => _timer != null;

  /// Timestamp of the first recorded frame, or 0 for an empty recording.
  int get _startMicros => frames.isEmpty ? 0 : frames.first.timestampMicros;

  /// Length of the recording.
  Duration get duration => frames.isEmpty
      ? Duration.zero
      : Duration(microseconds: frames.last.timestampMicros - _startMicros);

  /// Current playhead, relative to the start of the recording.
  Duration get position => Duration(microseconds: _positionMicros);

  /// Playback rate; 1.0 is real time. Must be positive.
  double get playbackSpeed => _playbackSpeed;

  set playbackSpeed(double value) {
    assert(value > 0, 'playback speed must be positive');
    _playbackSpeed = value;
  }

  /// Readies the source and shows the first frame without playing.
  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('RecordedSessionTrackingSource has been disposed');
    }
    _sequence = 0;
    _emittedIndex = null;
    _setStatus(TrackingSourceStatus.idle);
    _emitFrameAtPosition();
  }

  @override
  Future<void> disconnect() async {
    pause();
    if (_status == TrackingSourceStatus.disconnected) return;
    _setStatus(TrackingSourceStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _controller.close();
  }

  /// Starts playback. At the end of the recording, replays from the start.
  void play() {
    if (_disposed || frames.isEmpty || isPlaying) return;

    if (_positionMicros >= duration.inMicroseconds) seek(Duration.zero);

    _timer = Timer.periodic(tickInterval, (_) => _tick());
    _setStatus(TrackingSourceStatus.connected);
  }

  void pause() {
    if (!isPlaying) return;
    _timer?.cancel();
    _timer = null;
    // Idle rather than disconnected: the source still holds a recording and
    // still shows a frame, it just is not producing new ones.
    _setStatus(TrackingSourceStatus.idle);
  }

  /// Moves the playhead. Works while playing or paused, forwards or back.
  void seek(Duration position) {
    if (_disposed) return;
    _positionMicros =
        position.inMicroseconds.clamp(0, duration.inMicroseconds);
    _emitFrameAtPosition();
  }

  void _tick() {
    _positionMicros += (tickInterval.inMicroseconds * _playbackSpeed).round();

    if (_positionMicros >= duration.inMicroseconds) {
      _positionMicros = duration.inMicroseconds;
      _emitFrameAtPosition();
      pause();
      return;
    }

    _emitFrameAtPosition();
  }

  /// Emits the frame in force at the current position, if it is not the one
  /// already on screen.
  void _emitFrameAtPosition() {
    if (frames.isEmpty || _controller.isClosed) return;

    final index = indexAt(Duration(microseconds: _positionMicros));
    if (index == _emittedIndex) return;

    _emittedIndex = index;
    _controller.add(
      PositionFrameMessage(sequenceNumber: _sequence++, frame: frames[index]),
    );
  }

  /// Index of the last frame at or before [position].
  ///
  /// Binary search rather than a scan: scrubbing a long recording must not
  /// cost time proportional to how far the playhead moved, and backwards
  /// seeks must be as cheap as forwards ones.
  int indexAt(Duration position) {
    final target = _startMicros + position.inMicroseconds;

    var low = 0;
    var high = frames.length - 1;
    var best = 0;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (frames[mid].timestampMicros <= target) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  /// The frame currently in force, or null for an empty recording.
  PositionFrame? get currentFrame => frames.isEmpty
      ? null
      : frames[indexAt(Duration(microseconds: _positionMicros))];

  void _setStatus(TrackingSourceStatus status) {
    _status = status;
    if (_controller.isClosed) return;
    _controller.add(
      TrackingStatusMessage(
        sequenceNumber: _sequence++,
        // Status messages carry the playhead's absolute instant, so a
        // consumer that logs them can line them up with the frames.
        timestampMicros: _startMicros + _positionMicros,
        status: status,
      ),
    );
  }
}
