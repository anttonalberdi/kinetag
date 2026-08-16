/// Barrel export for Kinetag's tracking layer.
///
/// Consumers should import this and depend on [TrackingSource]; only
/// `tracking_providers.dart` names a concrete implementation.
library;

export 'simulator/match_simulation.dart';
export 'simulator/simulated_squad.dart';
export 'simulator/simulator_tracking_source.dart';
export 'tracking_message.dart';
export 'tracking_providers.dart';
export 'tracking_source.dart';
