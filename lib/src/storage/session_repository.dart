import '../domain/domain.dart';

/// Persistence boundary for recorded sessions.
///
/// Everything above this interface — the live view, the session browser,
/// analytics — speaks domain objects only. No widget builds SQL, and swapping
/// SQLite for a server-backed store later is one implementation, not a
/// rewrite.
///
/// Sample reads are deliberately *range* queries rather than "load the
/// session": a two-hour recording at 100 Hz per tag is tens of millions of
/// rows, and replay only ever needs the window it is showing.
abstract class SessionRepository {
  /// Inserts or updates session metadata, including its frozen setup.
  Future<void> saveSession(Session session);

  /// All sessions, newest first. Metadata only — never samples.
  Future<List<Session>> listSessions();

  Future<Session?> findSession(String id);

  /// Deletes a session and everything recorded under it.
  Future<void> deleteSession(String id);

  /// Appends [samples] to [sessionId]. Implementations are expected to write
  /// the whole list in one transaction.
  Future<void> appendSamples(String sessionId, List<PositionSample> samples);

  /// Samples in `[fromMicros, toMicros]`, in time order.
  ///
  /// Both bounds are inclusive and optional; [limit] caps the number of rows
  /// returned so a caller can never accidentally pull a whole recording into
  /// memory.
  Future<List<PositionSample>> samplesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  });

  /// The same rows as [samplesForSession], grouped into frames — the shape
  /// the canvas and the replay engine consume.
  Future<List<PositionFrame>> framesForSession(
    String sessionId, {
    int? fromMicros,
    int? toMicros,
    int? limit,
  });

  /// Number of samples stored for [sessionId]. The database, not the
  /// recorder, is the authority on what actually landed.
  Future<int> countSamples(String sessionId);

  /// First and last sample timestamps, or null when nothing was recorded.
  /// This is what a replay timeline is scaled against.
  Future<({int firstMicros, int lastMicros})?> timeRange(String sessionId);

  /// Releases any resources held (open database handles).
  Future<void> close();
}
