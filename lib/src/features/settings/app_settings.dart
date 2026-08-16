import 'package:meta/meta.dart';

import '../../analytics/analytics_thresholds.dart';
import '../../tracking/simulator/simulated_squad.dart';

/// User-adjustable knobs that are not part of a session's setup.
///
/// The distinction matters: a session snapshots its court, receivers and
/// roster **by value**, because moving an anchor later must not change what a
/// recording means. Settings are the opposite — they are how the operator
/// chooses to *interpret* and *capture* data, so they are deliberately not
/// frozen into a session. Change the speed ceiling and every session's
/// analytics recompute under the new one, which is the point.
///
/// Settings live in memory for now, like the setup layout: nothing in the
/// prototype persists configuration across restarts. [toJson] / [fromJson]
/// exist so that storing them is a wiring change rather than a rewrite.
@immutable
class AppSettings {
  /// Frames per second the tracking source produces.
  ///
  /// Changing this rebuilds the tracking source, so the UI blocks it while a
  /// recording is open — a recording whose sample rate changed halfway
  /// through would silently corrupt every rate-dependent metric.
  final int captureRateHz;

  /// Field players each side puts on court, excluding the goalkeeper — the
  /// `n` in a 1 + `n` line-up.
  ///
  /// A setting rather than part of setup because it says nothing about who
  /// exists: the roster still declares every player and every tag, and the
  /// ones beyond the line-up are simulated on the bench rather than dropped.
  /// Changing it rebuilds the tracking source, so the UI blocks it while a
  /// recording is open.
  final int fieldPlayersOnCourt;

  /// Default mounting height applied to receivers in a generated layout.
  final double receiverMountHeightMeters;

  /// How far outside the sidelines a generated layout places receivers.
  final double receiverMarginMeters;

  /// Noise rejection for derived movement metrics.
  final AnalyticsThresholds analytics;

  const AppSettings({
    this.captureRateHz = 20,
    this.fieldPlayersOnCourt = SimulatedSquad.defaultFieldPlayersOnCourt,
    this.receiverMountHeightMeters = defaultMountHeightMeters,
    this.receiverMarginMeters = defaultReceiverMarginMeters,
    this.analytics = AnalyticsThresholds.defaults,
  });

  static const AppSettings defaults = AppSettings();

  /// Above head height, which is where UWB anchors belong: a body between an
  /// anchor and a tag blocks the ranging signal.
  static const double defaultMountHeightMeters = 2.4;

  /// Just outside the sideline, close enough to a real hall's wall mountings.
  static const double defaultReceiverMarginMeters = 1.2;

  /// Bounds offered by the settings UI.
  ///
  /// The upper capture rate matches the 50–100 Hz per tag the real hub is
  /// designed for; the lower one keeps the live view watchable.
  static const int minCaptureRateHz = 5;
  static const int maxCaptureRateHz = 100;
  static const double minMountHeightMeters = 1.0;
  static const double maxMountHeightMeters = 12.0;
  static const double minReceiverMarginMeters = 0.0;
  static const double maxReceiverMarginMeters = 5.0;

  bool get isDefault => this == defaults;

  AppSettings copyWith({
    int? captureRateHz,
    int? fieldPlayersOnCourt,
    double? receiverMountHeightMeters,
    double? receiverMarginMeters,
    AnalyticsThresholds? analytics,
  }) =>
      AppSettings(
        captureRateHz: captureRateHz ?? this.captureRateHz,
        fieldPlayersOnCourt: fieldPlayersOnCourt ?? this.fieldPlayersOnCourt,
        receiverMountHeightMeters:
            receiverMountHeightMeters ?? this.receiverMountHeightMeters,
        receiverMarginMeters:
            receiverMarginMeters ?? this.receiverMarginMeters,
        analytics: analytics ?? this.analytics,
      );

  Map<String, dynamic> toJson() => {
        'captureRateHz': captureRateHz,
        'fieldPlayersOnCourt': fieldPlayersOnCourt,
        'receiverMountHeightMeters': receiverMountHeightMeters,
        'receiverMarginMeters': receiverMarginMeters,
        'maxPlausibleSpeedMps': analytics.maxPlausibleSpeedMps,
        'speedWindowMillis': analytics.speedWindow.inMilliseconds,
        'minConfidence': analytics.minConfidence,
      };

  /// Reads settings back, falling back to the default for any missing or
  /// unreadable field rather than failing to start.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    const fallback = AppSettings.defaults;
    return AppSettings(
      captureRateHz: (json['captureRateHz'] as num?)?.toInt() ??
          fallback.captureRateHz,
      fieldPlayersOnCourt: (json['fieldPlayersOnCourt'] as num?)?.toInt() ??
          fallback.fieldPlayersOnCourt,
      receiverMountHeightMeters:
          (json['receiverMountHeightMeters'] as num?)?.toDouble() ??
              fallback.receiverMountHeightMeters,
      receiverMarginMeters:
          (json['receiverMarginMeters'] as num?)?.toDouble() ??
              fallback.receiverMarginMeters,
      analytics: AnalyticsThresholds(
        maxPlausibleSpeedMps: (json['maxPlausibleSpeedMps'] as num?)
                ?.toDouble() ??
            fallback.analytics.maxPlausibleSpeedMps,
        speedWindow: Duration(
          milliseconds: (json['speedWindowMillis'] as num?)?.toInt() ??
              fallback.analytics.speedWindow.inMilliseconds,
        ),
        minConfidence: (json['minConfidence'] as num?)?.toDouble() ??
            fallback.analytics.minConfidence,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.captureRateHz == captureRateHz &&
          other.fieldPlayersOnCourt == fieldPlayersOnCourt &&
          other.receiverMountHeightMeters == receiverMountHeightMeters &&
          other.receiverMarginMeters == receiverMarginMeters &&
          other.analytics == analytics;

  @override
  int get hashCode => Object.hash(captureRateHz, fieldPlayersOnCourt,
      receiverMountHeightMeters, receiverMarginMeters, analytics);

  @override
  String toString() =>
      'AppSettings(${captureRateHz}Hz, 1+$fieldPlayersOnCourt, $analytics)';
}
