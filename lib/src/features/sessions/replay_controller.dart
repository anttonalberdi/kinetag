import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../domain/domain.dart';
import '../../storage/storage_providers.dart';
import '../../tracking/replay/recorded_session_tracking_source.dart';
import '../../tracking/tracking_message.dart';

/// Playback rates offered by the transport controls.
const List<double> kPlaybackSpeeds = [0.5, 1.0, 2.0, 4.0];

/// Everything the replay screen renders from.
@immutable
class ReplayState {
  final Session? session;
  final bool isLoading;
  final String? errorMessage;

  /// The frame currently on screen.
  final PositionFrame? frame;

  /// Playhead, relative to the start of the recording.
  final Duration position;
  final Duration duration;

  final bool isPlaying;
  final double speed;
  final int frameCount;

  const ReplayState({
    this.session,
    this.isLoading = false,
    this.errorMessage,
    this.frame,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.speed = 1.0,
    this.frameCount = 0,
  });

  bool get hasRecording => frameCount > 0;

  /// Absolute timestamp the playhead's zero corresponds to.
  ///
  /// Samples carry absolute times while the transport works in elapsed time,
  /// so anything that maps between the two — a chart of a player's speed, for
  /// instance — needs this offset. Derived from the frame on screen rather
  /// than stored, because the frame and the position are always set together
  /// from the same source and so cannot disagree. Null before the first frame,
  /// when there is nothing to align to.
  int? get recordingStartMicros => frame == null
      ? null
      : frame!.timestampMicros - position.inMicroseconds;

  /// Playhead as a fraction of the recording, in 0..1.
  double get progress {
    final total = duration.inMicroseconds;
    if (total <= 0) return 0;
    return (position.inMicroseconds / total).clamp(0.0, 1.0);
  }

  ReplayState copyWith({
    Session? session,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    PositionFrame? frame,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    double? speed,
    int? frameCount,
  }) =>
      ReplayState(
        session: session ?? this.session,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        frame: frame ?? this.frame,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        isPlaying: isPlaying ?? this.isPlaying,
        speed: speed ?? this.speed,
        frameCount: frameCount ?? this.frameCount,
      );
}

/// Drives replay of one recorded session.
///
/// The controller owns a [RecordedSessionTrackingSource] and consumes its
/// messages exactly as the live view consumes the simulator's — the canvas
/// downstream cannot tell the two apart. What it adds is the transport: play,
/// pause, seek and speed.
class ReplayController extends Notifier<ReplayState> {
  RecordedSessionTrackingSource? _source;
  StreamSubscription<TrackingMessage>? _subscription;

  @override
  ReplayState build() {
    ref.onDispose(_teardown);
    return const ReplayState();
  }

  /// Loads [session] and shows its first frame, paused.
  ///
  /// Frames are read in one go: prototype recordings are minutes long, and
  /// the repository's range queries are already in place for the windowed
  /// loader a match-length recording will eventually want.
  Future<void> open(Session session) async {
    await _teardown();

    state = ReplayState(session: session, isLoading: true);

    try {
      final frames = await ref
          .read(sessionRepositoryProvider)
          .framesForSession(session.id);

      final source = RecordedSessionTrackingSource(
        session: session,
        frames: frames,
      );
      _source = source;
      _subscription = source.messages.listen(_onMessage);

      await source.connect();

      state = state.copyWith(
        isLoading: false,
        duration: source.duration,
        frameCount: frames.length,
        position: Duration.zero,
        // Taken from the source rather than awaited from its stream: stream
        // delivery is asynchronous, and the screen must not paint an empty
        // court for a frame or two after opening a recording.
        frame: source.currentFrame,
        speed: source.playbackSpeed,
        isPlaying: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not load this session: $error',
      );
    }
  }

  void play() {
    _source?.play();
    state = state.copyWith(isPlaying: _source?.isPlaying ?? false);
  }

  void pause() {
    _source?.pause();
    state = state.copyWith(isPlaying: _source?.isPlaying ?? false);
  }

  void togglePlay() => state.isPlaying ? pause() : play();

  /// Moves the playhead.
  ///
  /// Position and frame are both taken straight from the source rather than
  /// waited for on its stream: a scrubber that lags the pointer by a stream
  /// hop feels broken, and the position must update even when the frame in
  /// force does not change.
  void seek(Duration position) {
    final source = _source;
    if (source == null) return;

    source.seek(position);
    state = state.copyWith(
      position: source.position,
      frame: source.currentFrame,
    );
  }

  /// Seeks to a fraction of the recording, for the timeline slider.
  void seekToProgress(double progress) => seek(
        Duration(
          microseconds:
              (state.duration.inMicroseconds * progress.clamp(0.0, 1.0))
                  .round(),
        ),
      );

  /// Steps one frame forwards or backwards; the fine control a scrubber
  /// cannot give.
  void step({required bool forward}) {
    final source = _source;
    if (source == null || source.frames.isEmpty) return;

    final index = source.indexAt(state.position);
    final target = (index + (forward ? 1 : -1)).clamp(
      0,
      source.frames.length - 1,
    );
    seek(
      Duration(
        microseconds: source.frames[target].timestampMicros -
            source.frames.first.timestampMicros,
      ),
    );
  }

  void setSpeed(double speed) {
    final source = _source;
    if (source == null) return;
    source.playbackSpeed = speed;
    state = state.copyWith(speed: speed);
  }

  /// Closes the current session and releases its frames.
  ///
  /// The state clears immediately; disposing the source is allowed to finish
  /// afterwards, so leaving replay never waits on teardown.
  Future<void> close() async {
    state = const ReplayState();
    await _teardown();
  }

  void _onMessage(TrackingMessage message) {
    // A message can still be in flight when the session is closed; it must
    // not resurrect a frame on a cleared screen.
    if (_source == null) return;

    switch (message) {
      case PositionFrameMessage(:final frame):
        state = state.copyWith(
          frame: frame,
          position: _source?.position ?? state.position,
          isPlaying: _source?.isPlaying ?? false,
        );
      case TrackingStatusMessage():
        state = state.copyWith(isPlaying: _source?.isPlaying ?? false);
      case TrackingErrorMessage(:final message):
        state = state.copyWith(errorMessage: message);
      case SequenceGapMessage():
        // A recording is read from disk in order; gaps cannot occur.
        break;
    }
  }

  /// Detaches the current source synchronously, then disposes it.
  ///
  /// The fields are cleared before the first await so that anything checking
  /// them — including [_onMessage] — sees "no session" the moment teardown
  /// begins rather than partway through it.
  Future<void> _teardown() async {
    final subscription = _subscription;
    final source = _source;
    _subscription = null;
    _source = null;

    await subscription?.cancel();
    await source?.dispose();
  }
}

final replayControllerProvider =
    NotifierProvider<ReplayController, ReplayState>(ReplayController.new);
