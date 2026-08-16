import 'tracking_message.dart';

/// Anything that produces [TrackingMessage]s: the simulator today, the
/// Kinetag hub over Wi-Fi later, and a stored recording during replay.
///
/// ## Why an interface at this point
///
/// Everything downstream — the live view, the recorder, analytics — consumes
/// this stream and nothing else. That is what allows
/// `KinetagHardwareTrackingSource` and `RecordedSessionTrackingSource` to be
/// dropped in as a single provider override without any screen changing, and
/// it is why the coordinate convention (world +Y down, metres, integer
/// microsecond timestamps) must be established *here*, at the boundary:
/// hardware that reports some other convention is adapted inside its own
/// source implementation, never further in.
///
/// ## Contract
///
/// - [messages] is a **broadcast** stream: the live view and the recorder
///   subscribe simultaneously. Messages emitted while nobody is listening are
///   dropped, so subscribe before calling [connect].
/// - Messages carry sequence numbers that are monotonic within one
///   connection and restart at 0 on each [connect].
/// - [connect] and [disconnect] are idempotent.
/// - Recoverable problems arrive as `TrackingErrorMessage`; only a fatal,
///   unrecoverable failure closes the stream.
/// - After [dispose] the source is unusable and [messages] is closed.
abstract class TrackingSource {
  /// Live stream of everything this source produces.
  Stream<TrackingMessage> get messages;

  /// Current lifecycle state, for consumers that attach mid-stream and need
  /// to render a status without waiting for the next status message.
  TrackingSourceStatus get status;

  /// Starts producing data. Safe to call when already connected.
  Future<void> connect();

  /// Stops producing data but leaves the source reusable.
  Future<void> disconnect();

  /// Releases all resources and closes [messages]. Not reusable afterwards.
  Future<void> dispose();
}
