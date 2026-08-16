/// Connection state of a piece of Kinetag hardware (receiver or tag).
///
/// Named with a `Device` prefix to avoid colliding with Flutter's own
/// `ConnectionState` enum used by `StreamBuilder`/`FutureBuilder`.
enum DeviceConnectionState {
  connected,
  disconnected,

  /// No information yet — e.g. a simulated device, or hardware not yet polled.
  unknown,
}
