import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../domain/domain.dart';
import '../../recording/recording_providers.dart';
import '../../storage/storage_providers.dart';
import '../../tracking/tracking_message.dart';
import '../../tracking/tracking_providers.dart';
import '../setup/setup_state.dart';
import 'live_roster.dart';

/// Everything the live view renders from.
@immutable
class LiveState {
  final TrackingSourceStatus status;

  /// The most recent frame, or null before the first one arrives.
  final PositionFrame? latestFrame;

  /// Frames seen since the current connection began.
  final int framesReceived;

  /// Time spanned by the frames received so far.
  final Duration liveElapsed;

  /// The recording in progress, or null when only monitoring.
  final Session? recordingSession;

  final int recordedSampleCount;
  final Duration recordingElapsed;

  /// The session finished by the most recent stop, for the confirmation the
  /// UI shows afterwards.
  final Session? lastCompletedSession;

  /// Messages the source reported as lost. Zero for the simulator; real
  /// Wi-Fi transport is what makes this worth surfacing.
  final int droppedMessages;

  final String? errorMessage;

  const LiveState({
    this.status = TrackingSourceStatus.disconnected,
    this.latestFrame,
    this.framesReceived = 0,
    this.liveElapsed = Duration.zero,
    this.recordingSession,
    this.recordedSampleCount = 0,
    this.recordingElapsed = Duration.zero,
    this.lastCompletedSession,
    this.droppedMessages = 0,
    this.errorMessage,
  });

  bool get isRecording => recordingSession != null;
  bool get isConnected => status == TrackingSourceStatus.connected;

  /// Tags visible in the latest frame.
  int get trackedTagCount => latestFrame?.samples.length ?? 0;

  LiveState copyWith({
    TrackingSourceStatus? status,
    PositionFrame? latestFrame,
    int? framesReceived,
    Duration? liveElapsed,
    Session? recordingSession,
    bool clearRecording = false,
    int? recordedSampleCount,
    Duration? recordingElapsed,
    Session? lastCompletedSession,
    int? droppedMessages,
    String? errorMessage,
    bool clearError = false,
  }) =>
      LiveState(
        status: status ?? this.status,
        latestFrame: latestFrame ?? this.latestFrame,
        framesReceived: framesReceived ?? this.framesReceived,
        liveElapsed: liveElapsed ?? this.liveElapsed,
        recordingSession:
            clearRecording ? null : (recordingSession ?? this.recordingSession),
        recordedSampleCount: recordedSampleCount ?? this.recordedSampleCount,
        recordingElapsed: recordingElapsed ?? this.recordingElapsed,
        lastCompletedSession: lastCompletedSession ?? this.lastCompletedSession,
        droppedMessages: droppedMessages ?? this.droppedMessages,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Consumes a `TrackingSource` and owns the live view's state, including
/// recording.
///
/// Two rules shape this class:
///
/// 1. **It never names a concrete source.** It watches `trackingSourceProvider`
///    and handles the sealed `TrackingMessage` type, so replacing the
///    simulator with hardware or a replay changes nothing here.
/// 2. **Elapsed times come from frame timestamps, never from the wall clock.**
///    What the operator sees ticking is therefore exactly what was captured;
///    if the pipeline stalls, the clock visibly stalls with it instead of
///    quietly drifting away from the data.
class LiveController extends Notifier<LiveState> {
  static const Uuid _uuid = Uuid();

  int? _recordingStartMicros;
  int? _liveStartMicros;

  @override
  LiveState build() {
    final source = ref.watch(trackingSourceProvider);

    final subscription = source.messages.listen(_onMessage);
    ref.onDispose(subscription.cancel);

    _liveStartMicros = null;
    _recordingStartMicros = null;

    return LiveState(status: source.status);
  }

  /// Starts the tracking source. Safe to call repeatedly.
  Future<void> start() => ref.read(trackingSourceProvider).connect();

  /// Stops tracking, closing any recording first so nothing is left dangling.
  Future<void> stop() async {
    if (state.isRecording) await stopRecording();
    await ref.read(trackingSourceProvider).disconnect();
  }

  /// Opens a recording against a **snapshot** of the current setup.
  ///
  /// The court and receiver positions are read once, here, and copied into
  /// the session by value. Moving a receiver later must not change what a
  /// stored recording means.
  Future<void> startRecording({DateTime? now}) async {
    if (state.isRecording) return;

    final setup = ref.read(setupControllerProvider);
    final roster = ref.read(liveRosterProvider);
    final createdAt = (now ?? DateTime.now()).toUtc();

    final session = Session(
      id: _uuid.v4(),
      name: 'Session ${_defaultSessionName(now ?? DateTime.now())}',
      createdAt: createdAt,
      court: setup.court,
      receivers: List.of(setup.receivers),
      tags: List.of(roster.tags),
      players: List.of(roster.players),
      tagAssignments: List.of(roster.assignments),
      status: SessionStatus.recording,
      startedAt: createdAt,
    );

    await ref.read(recordingSinkProvider).begin(session);

    // Timed from the first frame that actually lands in the recording, not
    // from the button press, so elapsed time and stored data agree.
    _recordingStartMicros = null;
    state = state.copyWith(
      recordingSession: session,
      recordedSampleCount: 0,
      recordingElapsed: Duration.zero,
    );
  }

  /// Closes the recording and returns the completed session.
  Future<Session?> stopRecording() async {
    if (!state.isRecording) return null;

    final sink = ref.read(recordingSinkProvider);
    final completed = await sink.finish();
    _recordingStartMicros = null;

    // Storage refreshes only when a recording ends, so the session browser
    // never polls.
    ref.invalidate(sessionListProvider);

    // Writes are batched and asynchronous, so a storage failure can only be
    // reported after the fact — but it must be reported: the completed
    // session's count comes from what actually reached the database.
    final writeError = sink.lastWriteError;

    state = state.copyWith(
      clearRecording: true,
      lastCompletedSession: completed,
      recordedSampleCount: completed.sampleCount,
      errorMessage:
          writeError == null ? null : 'Storage error: $writeError',
      clearError: writeError == null,
    );
    return completed;
  }

  void _onMessage(TrackingMessage message) {
    // Exhaustive over the sealed hierarchy: a new message kind added for
    // hardware will not compile until it is handled here.
    switch (message) {
      case PositionFrameMessage(:final frame):
        _onFrame(frame);
      case TrackingStatusMessage(:final status, :final detail):
        _onStatus(status, detail);
      case TrackingErrorMessage(:final message):
        state = state.copyWith(errorMessage: message);
      case SequenceGapMessage(:final missingCount):
        state = state.copyWith(
          droppedMessages: state.droppedMessages + missingCount,
        );
    }
  }

  void _onFrame(PositionFrame frame) {
    _liveStartMicros ??= frame.timestampMicros;

    var recordedSampleCount = state.recordedSampleCount;
    var recordingElapsed = state.recordingElapsed;

    if (state.isRecording) {
      ref.read(recordingSinkProvider).add(frame);
      _recordingStartMicros ??= frame.timestampMicros;
      recordedSampleCount += frame.samples.length;
      recordingElapsed = Duration(
        microseconds: frame.timestampMicros - _recordingStartMicros!,
      );
    }

    state = state.copyWith(
      latestFrame: frame,
      framesReceived: state.framesReceived + 1,
      liveElapsed:
          Duration(microseconds: frame.timestampMicros - _liveStartMicros!),
      recordedSampleCount: recordedSampleCount,
      recordingElapsed: recordingElapsed,
    );
  }

  void _onStatus(TrackingSourceStatus status, String? detail) {
    // A fresh connection restarts the live clock; stale elapsed time from a
    // previous connection would be a lie.
    if (status == TrackingSourceStatus.connecting) {
      _liveStartMicros = null;
      state = state.copyWith(
        status: status,
        framesReceived: 0,
        liveElapsed: Duration.zero,
        droppedMessages: 0,
        clearError: true,
      );
      return;
    }

    state = state.copyWith(
      status: status,
      errorMessage: status == TrackingSourceStatus.error ? detail : null,
      clearError: status != TrackingSourceStatus.error,
    );
  }

  /// `16 Aug 2026 14:32` — short, sortable enough to read in a list, and free
  /// of a localisation dependency.
  static String _defaultSessionName(DateTime when) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = when.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year} $hh:$mm';
  }
}

final liveControllerProvider =
    NotifierProvider<LiveController, LiveState>(LiveController.new);
