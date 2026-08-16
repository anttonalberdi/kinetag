/// Formats [duration] as `mm:ss`, or `h:mm:ss` once it passes an hour.
///
/// Deliberately hand-rolled rather than pulled from `intl`: elapsed match
/// time is not a localised wall-clock time, and a training session that reads
/// `1:04:12` in Copenhagen must read the same in Reykjavík.
String formatElapsed(Duration duration) {
  final negative = duration.isNegative;
  final total = duration.abs();

  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);

  final body = hours > 0
      ? '$hours:${_two(minutes)}:${_two(seconds)}'
      : '${_two(minutes)}:${_two(seconds)}';

  return negative ? '-$body' : body;
}

String _two(int value) => value.toString().padLeft(2, '0');
