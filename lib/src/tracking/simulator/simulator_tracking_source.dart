import 'dart:async';

import '../../domain/domain.dart';
import '../tracking_message.dart';
import '../tracking_source.dart';
import 'match_simulation.dart';
import 'simulated_squad.dart';

/// A [TrackingSource] that fabricates a handball match.
///
/// Stands in for the hub until real UWB hardware exists, and stays useful
/// afterwards for demos, tests and UI work without a hall full of anchors.
///
/// ## Timing
///
/// Frame timestamps are **synthetic and exactly regular**: the wall clock is
/// read once at [connect] and every subsequent frame is stamped
/// `start + n × period`. Deriving each timestamp from `DateTime.now()` instead
/// would fold Dart timer jitter (milliseconds, routinely) into the data, and
/// since velocity is `dx / dt` that jitter would surface as speed noise in
/// exactly the analytics this simulator exists to feed. Real hardware
/// timestamps at the source for the same reason. The cost is that if the
/// event loop stalls, simulated time falls behind the wall clock; the elapsed
/// time shown during recording is therefore read from frame timestamps, so
/// what is displayed always matches what is stored.
class SimulatorTrackingSource implements TrackingSource {
  /// Frames per second. 20 Hz is enough to look continuous while leaving
  /// headroom; the eventual target is 50–100 Hz per tag.
  static const int defaultSampleRateHz = 20;

  final Court court;
  final SimulatedSquad squad;
  final int sampleRateHz;
  final int seed;

  /// How often each side exchanges a field player with a substitute; zero
  /// keeps the starting line-up on for the whole connection.
  final Duration substitutionInterval;

  /// Injectable wall clock, so tests can pin the recording's start instant.
  final DateTime Function() _clock;

  final StreamController<TrackingMessage> _controller =
      StreamController<TrackingMessage>.broadcast();

  MatchSimulation? _simulation;
  Timer? _timer;

  int _sequence = 0;
  int _frameIndex = 0;
  int _startMicros = 0;
  bool _disposed = false;
  TrackingSourceStatus _status = TrackingSourceStatus.disconnected;

  SimulatorTrackingSource({
    required this.court,
    SimulatedSquad? squad,
    this.sampleRateHz = defaultSampleRateHz,
    this.seed = 20260816,
    this.substitutionInterval = MatchSimulation.defaultSubstitutionInterval,
    DateTime Function()? clock,
  })  : assert(sampleRateHz > 0, 'sampleRateHz must be positive'),
        squad = squad ?? SimulatedSquad.handballTeams(),
        _clock = clock ?? DateTime.now;

  /// Nominal interval between frames, in microseconds.
  int get framePeriodMicros => 1000000 ~/ sampleRateHz;

  @override
  Stream<TrackingMessage> get messages => _controller.stream;

  @override
  TrackingSourceStatus get status => _status;

  /// Simulated time produced since the current connection began.
  Duration get elapsed => _simulation?.elapsed ?? Duration.zero;

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('SimulatorTrackingSource has been disposed');
    }
    if (_status == TrackingSourceStatus.connected) return;

    // Sequence numbers are documented as per-connection and starting at 0.
    _sequence = 0;
    _frameIndex = 0;
    _emitStatus(TrackingSourceStatus.connecting);

    _simulation = MatchSimulation(
      court: court,
      squad: squad,
      seed: seed,
      substitutionInterval: substitutionInterval,
    );
    _startMicros = _clock().toUtc().microsecondsSinceEpoch;
    _timer = Timer.periodic(
      Duration(microseconds: framePeriodMicros),
      (_) => _emitFrame(),
    );

    _emitStatus(TrackingSourceStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _simulation = null;
    if (_status == TrackingSourceStatus.disconnected) return;
    _emitStatus(TrackingSourceStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _controller.close();
  }

  void _emitFrame() {
    final simulation = _simulation;
    if (simulation == null || _controller.isClosed) return;

    _frameIndex++;
    final frame = simulation.advance(
      dtMicros: framePeriodMicros,
      timestampMicros: _startMicros + _frameIndex * framePeriodMicros,
    );
    _controller.add(
      PositionFrameMessage(sequenceNumber: _sequence++, frame: frame),
    );
  }

  void _emitStatus(TrackingSourceStatus status, {String? detail}) {
    _status = status;
    if (_controller.isClosed) return;
    _controller.add(
      TrackingStatusMessage(
        sequenceNumber: _sequence++,
        timestampMicros: _clock().toUtc().microsecondsSinceEpoch,
        status: status,
        detail: detail,
      ),
    );
  }
}
