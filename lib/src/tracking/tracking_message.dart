import 'package:meta/meta.dart';

import '../domain/position_frame.dart';

/// Lifecycle state of a [TrackingSource].
enum TrackingSourceStatus {
  disconnected,
  connecting,
  connected,

  /// Connected but not currently producing data (e.g. replay paused).
  idle,
  error,
}

/// Anything a [TrackingSource] can emit.
///
/// Sealed so that `switch` over messages is exhaustively checked: when
/// hardware adds a new message kind, every consumer fails to compile until it
/// is handled, rather than silently ignoring it at runtime.
///
/// Every message carries a [sequenceNumber]. The simulator simply counts up,
/// but the field exists from the start because the future hub protocol
/// (§15) uses sequence numbers to detect dropped packets over Wi-Fi and to
/// request retransmission from the hub's rolling buffer. Retrofitting it
/// later would mean changing every message construction site.
@immutable
sealed class TrackingMessage {
  /// Monotonically increasing per source connection, starting at 0.
  final int sequenceNumber;

  /// Microseconds since the Unix epoch, UTC.
  final int timestampMicros;

  const TrackingMessage({
    required this.sequenceNumber,
    required this.timestampMicros,
  });
}

/// A batch of tag positions for one instant — the payload the UI renders.
@immutable
final class PositionFrameMessage extends TrackingMessage {
  final PositionFrame frame;

  /// The message timestamp is always taken from the frame, so the two can
  /// never disagree.
  ///
  /// `sequenceNumber` cannot be a super parameter here: deriving
  /// `timestampMicros` from [frame] requires an explicit super constructor
  /// invocation, and Dart forbids combining the two forms.
  // ignore: use_super_parameters
  PositionFrameMessage({
    required int sequenceNumber,
    required this.frame,
  })  : super(
          sequenceNumber: sequenceNumber,
          timestampMicros: frame.timestampMicros,
        );

  @override
  String toString() => 'PositionFrameMessage(seq=$sequenceNumber, $frame)';
}

/// The source's connection state changed.
@immutable
final class TrackingStatusMessage extends TrackingMessage {
  final TrackingSourceStatus status;

  /// Human-readable detail, e.g. "hub unreachable".
  final String? detail;

  const TrackingStatusMessage({
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.status,
    this.detail,
  });

  @override
  String toString() =>
      'TrackingStatusMessage(${status.name}${detail == null ? '' : ': $detail'})';
}

/// A recoverable error. Fatal problems close the stream instead.
@immutable
final class TrackingErrorMessage extends TrackingMessage {
  final String message;
  final Object? cause;

  const TrackingErrorMessage({
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.message,
    this.cause,
  });

  @override
  String toString() => 'TrackingErrorMessage($message)';
}

/// Emitted when a gap is detected in the incoming sequence numbers.
///
/// Unused by the simulator, which never drops frames. Present so that the
/// live view's "tracking status" indicator has a defined message to react to
/// once real Wi-Fi transport is introduced.
@immutable
final class SequenceGapMessage extends TrackingMessage {
  /// Last sequence number received before the gap.
  final int lastSequence;

  /// First sequence number received after the gap.
  final int resumedSequence;

  const SequenceGapMessage({
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.lastSequence,
    required this.resumedSequence,
  });

  /// How many messages were lost.
  int get missingCount => resumedSequence - lastSequence - 1;

  @override
  String toString() => 'SequenceGapMessage($missingCount missing)';
}
