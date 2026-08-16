import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/session_metrics.dart';
import 'package:kinetag/src/analytics/speed_zones.dart';

/// A track whose windowed speeds are supplied directly, so the banding can be
/// checked without going through position arithmetic first.
PlayerTrackMetrics trackWithSpeeds(
  List<double> speeds, {
  int stepMicros = 100000,
  int firstMicros = 0,
}) =>
    PlayerTrackMetrics(
      tagId: 'tag-0',
      distanceMeters: 0,
      maxSpeedMps: speeds.isEmpty ? 0 : speeds.reduce((a, b) => a > b ? a : b),
      averageSpeedMps: 0,
      trackedDuration: Duration(microseconds: speeds.length * stepMicros),
      sampleCount: speeds.length,
      discardedSteps: 0,
      speedTimesMicros: [
        for (var i = 0; i < speeds.length; i++) firstMicros + i * stepMicros,
      ],
      speeds: speeds,
    );

void main() {
  group('SpeedZone.forSpeed', () {
    test('puts each speed in the band its lower bound opens', () {
      expect(SpeedZone.forSpeed(0), SpeedZone.standing);
      expect(SpeedZone.forSpeed(0.59), SpeedZone.standing);
      expect(SpeedZone.forSpeed(0.6), SpeedZone.walking);
      expect(SpeedZone.forSpeed(2.0), SpeedZone.jogging);
      expect(SpeedZone.forSpeed(3.99), SpeedZone.jogging);
      expect(SpeedZone.forSpeed(4.0), SpeedZone.running);
      expect(SpeedZone.forSpeed(5.5), SpeedZone.sprinting);
      expect(SpeedZone.forSpeed(11.0), SpeedZone.sprinting);
    });
  });

  group('SpeedZoneBreakdown', () {
    test('credits each speed with the time since the previous one', () {
      // Five samples 100 ms apart: four intervals, each credited to the band
      // of the speed that ends it. The first sample opens no interval.
      final breakdown = SpeedZoneBreakdown.fromTrack(
        trackWithSpeeds([0.0, 0.0, 3.0, 3.0, 7.0]),
      );

      expect(breakdown.inZone(SpeedZone.standing),
          const Duration(milliseconds: 100));
      expect(breakdown.inZone(SpeedZone.jogging),
          const Duration(milliseconds: 200));
      expect(breakdown.inZone(SpeedZone.sprinting),
          const Duration(milliseconds: 100));
      expect(breakdown.total, const Duration(milliseconds: 400));
      expect(breakdown.shareOf(SpeedZone.jogging), closeTo(0.5, 1e-9));
      expect(breakdown.shareOf(SpeedZone.walking), 0);
    });

    test('caps a dropout so it cannot fill a band', () {
      // A 30-second gap between two sprint samples is a tag that went quiet,
      // not half a minute of sprinting.
      final track = PlayerTrackMetrics(
        tagId: 'tag-0',
        distanceMeters: 0,
        maxSpeedMps: 7,
        averageSpeedMps: 0,
        trackedDuration: const Duration(seconds: 30),
        sampleCount: 2,
        discardedSteps: 0,
        speedTimesMicros: const [0, 30000000],
        speeds: const [7.0, 7.0],
      );

      expect(
        SpeedZoneBreakdown.fromTrack(track).inZone(SpeedZone.sprinting),
        SpeedZoneBreakdown.maxAttributableGap,
      );
    });

    test('is empty for a track with no measured speeds', () {
      final breakdown = SpeedZoneBreakdown.fromTrack(trackWithSpeeds(const []));

      expect(breakdown.isEmpty, isTrue);
      expect(breakdown.total, Duration.zero);
      expect(breakdown.shareOf(SpeedZone.standing), 0);
    });
  });
}
