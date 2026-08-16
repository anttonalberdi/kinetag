import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_providers.dart';
import 'session_metrics.dart';

/// Movement metrics for a recorded session, computed on demand.
///
/// A `FutureProvider` rather than a stored column: metrics are derived data
/// (decision 6), so they are recomputed from the samples whenever they are
/// asked for. Riverpod caches the result for as long as something is
/// watching, which is what keeps "recompute every time" from meaning
/// "recompute every frame".
final sessionMetricsProvider =
    FutureProvider.family<SessionMetrics, String>((ref, sessionId) async {
  final samples =
      await ref.watch(sessionRepositoryProvider).samplesForSession(sessionId);
  return SessionMetrics.fromSamples(samples);
});
