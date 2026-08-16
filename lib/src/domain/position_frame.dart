import 'package:meta/meta.dart';

import 'position_sample.dart';

/// All tag positions known at one instant.
///
/// Grouping samples into frames is what keeps rendering cheap: the live view
/// rebuilds once per frame rather than once per tag per sample. At 30 tags ×
/// 100 Hz that is the difference between 3000 and 100 UI notifications per
/// second.
///
/// A frame is also the natural unit for replay seeking — the replay engine
/// looks up the frame bracketing a requested time instead of scanning
/// per-tag streams independently.
@immutable
class PositionFrame {
  /// Microseconds since the Unix epoch, UTC. Represents the frame's nominal
  /// instant; individual samples may carry slightly different timestamps if
  /// receivers are not perfectly synchronised.
  final int timestampMicros;

  final List<PositionSample> samples;

  const PositionFrame({
    required this.timestampMicros,
    required this.samples,
  });

  /// Groups loose [samples] into frames by exact timestamp.
  ///
  /// Used when reading recordings back from storage, where samples arrive as
  /// a flat time-ordered list.
  static List<PositionFrame> groupByTimestamp(
      Iterable<PositionSample> samples) {
    final byTime = <int, List<PositionSample>>{};
    for (final sample in samples) {
      (byTime[sample.timestampMicros] ??= []).add(sample);
    }
    final times = byTime.keys.toList()..sort();
    return [
      for (final t in times)
        PositionFrame(timestampMicros: t, samples: byTime[t]!),
    ];
  }

  DateTime get timestamp =>
      DateTime.fromMicrosecondsSinceEpoch(timestampMicros, isUtc: true);

  /// The sample for [tagId] in this frame, or null if that tag was not seen.
  PositionSample? sampleForTag(String tagId) {
    for (final sample in samples) {
      if (sample.tagId == tagId) return sample;
    }
    return null;
  }

  Iterable<String> get tagIds => samples.map((s) => s.tagId);

  Map<String, dynamic> toJson() => {
        'timestampMicros': timestampMicros,
        'samples': samples.map((s) => s.toJson()).toList(),
      };

  factory PositionFrame.fromJson(Map<String, dynamic> json) => PositionFrame(
        timestampMicros: json['timestampMicros'] as int,
        samples: (json['samples'] as List)
            .map((s) => PositionSample.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  @override
  String toString() =>
      'PositionFrame(t=$timestampMicros, ${samples.length} samples)';
}
