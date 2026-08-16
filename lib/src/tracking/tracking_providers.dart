import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/domain.dart';
import 'simulator/simulated_squad.dart';
import 'simulator/simulator_tracking_source.dart';
import 'tracking_message.dart';
import 'tracking_source.dart';

/// The court tracking data is produced for.
///
/// Defaults to a regulation handball court and is overridden in `main.dart`
/// to follow whatever the setup screen holds. The indirection keeps the
/// tracking layer free of any dependency on a UI feature: the app layer wires
/// the two together, the tracking layer only knows it needs a [Court].
final trackingCourtProvider = Provider<Court>((ref) => Court.handball());

/// Frames per second the source produces.
///
/// Overridden in `main.dart` from settings, for the same reason as
/// [trackingCourtProvider]: the tracking layer must not know that a settings
/// screen exists.
final trackingSampleRateProvider =
    Provider<int>((ref) => SimulatorTrackingSource.defaultSampleRateHz);

/// The tags to simulate, and how each of them moves.
///
/// Overridden in `main.dart` from the roster entered in setup, so the tags
/// that appear on court are the ones the operator defined. [SimulatedSquad]
/// compares equal when the simulated movement is unchanged, which is what
/// keeps a rename in setup from restarting the source below.
final simulatedSquadProvider =
    Provider<SimulatedSquad>((ref) => SimulatedSquad.handballTeams());

/// The single seam where the simulator is replaced by hardware or replay.
///
/// Every consumer — live view, recorder, analytics — depends on
/// [TrackingSource], never on the simulator, so swapping in
/// `KinetagHardwareTrackingSource` or `RecordedSessionTrackingSource` is an
/// override here and nothing else.
final trackingSourceProvider = Provider<TrackingSource>((ref) {
  final source = SimulatorTrackingSource(
    court: ref.watch(trackingCourtProvider),
    squad: ref.watch(simulatedSquadProvider),
    sampleRateHz: ref.watch(trackingSampleRateProvider),
  );
  ref.onDispose(source.dispose);
  return source;
});

/// Raw message stream, for consumers that need status and errors as well as
/// frames.
final trackingMessagesProvider = StreamProvider<TrackingMessage>(
  (ref) => ref.watch(trackingSourceProvider).messages,
);
