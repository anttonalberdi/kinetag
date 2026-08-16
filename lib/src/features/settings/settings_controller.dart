import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/analytics_thresholds.dart';
import '../../tracking/simulator/simulated_squad.dart';
import 'app_settings.dart';

/// Owns [AppSettings] and clamps every write into a usable range.
///
/// Clamping lives here rather than in the widgets so that a slider, a text
/// field and a future config file all get the same guarantees: no consumer of
/// `appSettingsProvider` has to defend itself against a zero-length speed
/// window or a negative capture rate.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.defaults;

  void setCaptureRateHz(int hz) => state = state.copyWith(
        captureRateHz:
            hz.clamp(AppSettings.minCaptureRateHz, AppSettings.maxCaptureRateHz),
      );

  void setFieldPlayersOnCourt(int count) => state = state.copyWith(
        fieldPlayersOnCourt: count.clamp(
          SimulatedSquad.minFieldPlayersOnCourt,
          SimulatedSquad.maxFieldPlayersOnCourt,
        ),
      );

  /// Sets the rotation period, or turns rotation off with anything at or below
  /// zero.
  ///
  /// Off is a real answer rather than an out-of-range one — a match played
  /// without substitutions is a match — so it is snapped to rather than
  /// clamped away.
  void setSubstitutionIntervalSeconds(int seconds) => state = state.copyWith(
        substitutionIntervalSeconds: seconds <= 0
            ? AppSettings.substitutionOffSeconds
            : seconds.clamp(
                AppSettings.minSubstitutionIntervalSeconds,
                AppSettings.maxSubstitutionIntervalSeconds,
              ),
      );

  void setReceiverMountHeightMeters(double metres) => state = state.copyWith(
        receiverMountHeightMeters: metres.clamp(
          AppSettings.minMountHeightMeters,
          AppSettings.maxMountHeightMeters,
        ),
      );

  void setReceiverMarginMeters(double metres) => state = state.copyWith(
        receiverMarginMeters: metres.clamp(
          AppSettings.minReceiverMarginMeters,
          AppSettings.maxReceiverMarginMeters,
        ),
      );

  void setMaxPlausibleSpeedMps(double mps) => _updateAnalytics(
        (a) => a.copyWith(
          maxPlausibleSpeedMps: mps.clamp(
            AnalyticsThresholds.minSpeedCeilingMps,
            AnalyticsThresholds.maxSpeedCeilingMps,
          ),
        ),
      );

  void setSpeedWindow(Duration window) => _updateAnalytics(
        (a) => a.copyWith(
          speedWindow: Duration(
            milliseconds: window.inMilliseconds.clamp(
              AnalyticsThresholds.minSpeedWindow.inMilliseconds,
              AnalyticsThresholds.maxSpeedWindow.inMilliseconds,
            ),
          ),
        ),
      );

  void setMinConfidence(double confidence) => _updateAnalytics(
        (a) => a.copyWith(minConfidence: confidence.clamp(0.0, 1.0)),
      );

  void resetToDefaults() => state = AppSettings.defaults;

  void _updateAnalytics(
    AnalyticsThresholds Function(AnalyticsThresholds) update,
  ) =>
      state = state.copyWith(analytics: update(state.analytics));
}

final appSettingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// The analytics thresholds alone.
///
/// Exposed separately so that recomputing a session's metrics is triggered by
/// a change to a *threshold*, not by an unrelated change to the capture rate.
final analyticsThresholdsProvider = Provider<AnalyticsThresholds>(
  (ref) => ref.watch(appSettingsProvider.select((s) => s.analytics)),
);
