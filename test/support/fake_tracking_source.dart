import 'dart:async';

import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/tracking/tracking_message.dart';
import 'package:kinetag/src/tracking/tracking_source.dart';

/// A [TrackingSource] driven by the test rather than by a timer.
///
/// Lets the live-view tests decide exactly which messages arrive and when,
/// which is the whole point of putting an interface between the UI and the
/// simulator.
class FakeTrackingSource implements TrackingSource {
  final StreamController<TrackingMessage> _controller =
      StreamController<TrackingMessage>.broadcast();

  int _sequence = 0;
  TrackingSourceStatus _status = TrackingSourceStatus.disconnected;

  int connectCount = 0;
  int disconnectCount = 0;

  @override
  Stream<TrackingMessage> get messages => _controller.stream;

  @override
  TrackingSourceStatus get status => _status;

  @override
  Future<void> connect() async {
    connectCount++;
    _sequence = 0;
    emitStatus(TrackingSourceStatus.connecting);
    emitStatus(TrackingSourceStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    emitStatus(TrackingSourceStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void emitStatus(TrackingSourceStatus status, {String? detail}) {
    _status = status;
    _controller.add(
      TrackingStatusMessage(
        sequenceNumber: _sequence++,
        timestampMicros: 0,
        status: status,
        detail: detail,
      ),
    );
  }

  void emitFrame(PositionFrame frame) => _controller.add(
        PositionFrameMessage(sequenceNumber: _sequence++, frame: frame),
      );

  void emitError(String message) => _controller.add(
        TrackingErrorMessage(
          sequenceNumber: _sequence++,
          timestampMicros: 0,
          message: message,
        ),
      );

  void emitGap({required int lastSequence, required int resumedSequence}) =>
      _controller.add(
        SequenceGapMessage(
          sequenceNumber: _sequence++,
          timestampMicros: 0,
          lastSequence: lastSequence,
          resumedSequence: resumedSequence,
        ),
      );
}

/// A frame of [tagCount] tags at [timestampMicros], laid out in a line so
/// positions are predictable.
PositionFrame testFrame({
  required int timestampMicros,
  int tagCount = 3,
  double y = 10,
}) =>
    PositionFrame(
      timestampMicros: timestampMicros,
      samples: [
        for (var i = 0; i < tagCount; i++)
          PositionSample(
            timestampMicros: timestampMicros,
            tagId: 'tag-$i',
            x: 5.0 + i * 5,
            y: y,
          ),
      ],
    );
