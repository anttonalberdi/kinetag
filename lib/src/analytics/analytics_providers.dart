import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/domain.dart';
import '../features/settings/settings_controller.dart';
import '../storage/storage_providers.dart';
import 'session_metrics.dart';

/// The stored samples of one recording, read once and shared.
///
/// Every analysis of a session — movement metrics, occupancy, whatever comes
/// next — starts from the same list, and a session's samples are the largest
/// thing the app reads from disk. Loading them behind their own provider means
/// two analyses of one session cost one read, and that changing a threshold
/// recomputes from memory instead of going back to SQLite.
///
/// Kept alive as long as something watches it, which for an open session means
/// until it is closed. That is a deliberate trade of memory for responsiveness:
/// the samples are what every figure on the analysis pages is derived from.
final sessionSamplesProvider =
    FutureProvider.family<List<PositionSample>, String>(
  (ref, sessionId) =>
      ref.watch(sessionRepositoryProvider).samplesForSession(sessionId),
);

/// Movement metrics for a recorded session, computed on demand.
///
/// A `FutureProvider` rather than a stored column: metrics are derived data
/// (decision 6), so they are recomputed from the samples whenever they are
/// asked for. Riverpod caches the result for as long as something is
/// watching, which is what keeps "recompute every time" from meaning
/// "recompute every frame".
///
/// Watching the thresholds is what makes the settings screen meaningful:
/// tightening the speed ceiling recomputes every open session's figures under
/// the new rule instead of leaving stale numbers on screen.
final sessionMetricsProvider =
    FutureProvider.family<SessionMetrics, String>((ref, sessionId) async {
  final thresholds = ref.watch(analyticsThresholdsProvider);
  final samples = await ref.watch(sessionSamplesProvider(sessionId).future);
  return SessionMetrics.fromSamples(samples, thresholds: thresholds);
});
