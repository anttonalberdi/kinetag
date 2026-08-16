import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/storage/session_repository.dart';

/// An in-memory [SessionRepository] whose futures complete immediately.
///
/// Widget tests run on a fake clock, so real database I/O — which happens on
/// another thread — never completes inside `pumpAndSettle`. This fake keeps
/// screen tests about the screen; the SQL itself is covered by the repository
/// tests, which run against real SQLite.
class FakeSessionRepository implements SessionRepository {
  final Map<String, Session> _sessions = {};
  final Map<String, List<PositionSample>> _samples = {};

  int deleteCount = 0;

  @override
  Future<void> saveSession(Session session) async =>
      _sessions[session.id] = session;

  @override
  Future<List<Session>> listSessions() async {
    final sessions = _sessions.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  @override
  Future<Session?> findSession(String id) async => _sessions[id];

  @override
  Future<void> deleteSession(String id) async {
    deleteCount++;
    _sessions.remove(id);
    _samples.remove(id);
  }

  @override
  Future<void> appendSamples(
    String sessionId,
    List<PositionSample> samples,
  ) async =>
      (_samples[sessionId] ??= []).addAll(samples);

  @override
  Future<List<PositionSample>> samplesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  }) async {
    final all = [...?_samples[sessionId]]
      ..sort((a, b) => a.timestampMicros.compareTo(b.timestampMicros));

    final filtered = all
        .where((s) =>
            (fromMicros == null || s.timestampMicros >= fromMicros) &&
            (toMicros == null || s.timestampMicros <= toMicros))
        .toList();

    return limit == null || limit >= filtered.length
        ? filtered
        : filtered.sublist(0, limit);
  }

  @override
  Future<List<PositionFrame>> framesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  }) async =>
      PositionFrame.groupByTimestamp(
        await samplesForSession(
          sessionId,
          fromMicros: fromMicros,
          toMicros: toMicros,
          limit: limit,
        ),
      );

  @override
  Future<int> countSamples(String sessionId) async =>
      _samples[sessionId]?.length ?? 0;

  @override
  Future<({int firstMicros, int lastMicros})?> timeRange(
      String sessionId) async {
    final samples = await samplesForSession(sessionId);
    if (samples.isEmpty) return null;
    return (
      firstMicros: samples.first.timestampMicros,
      lastMicros: samples.last.timestampMicros,
    );
  }

  @override
  Future<void> close() async {}
}
