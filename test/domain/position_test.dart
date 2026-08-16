import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';

const kT0 = 1755331200000000; // arbitrary epoch micros

void main() {
  group('PositionSample', () {
    test('computes planar distance between samples', () {
      const a = PositionSample(
          timestampMicros: kT0, tagId: 't1', x: 0, y: 0);
      const b = PositionSample(
          timestampMicros: kT0, tagId: 't1', x: 3, y: 4);

      expect(a.distanceTo(b), closeTo(5.0, 1e-9));
    });

    test('computes speed in metres per second', () {
      // 5 m covered in 500 ms -> 10 m/s.
      const a = PositionSample(
          timestampMicros: kT0, tagId: 't1', x: 0, y: 0);
      const b = PositionSample(
          timestampMicros: kT0 + 500000, tagId: 't1', x: 3, y: 4);

      expect(a.speedTo(b), closeTo(10.0, 1e-9));
    });

    test('returns zero speed for duplicate timestamps instead of dividing by '
        'zero', () {
      // Hardware retransmission can legitimately deliver two samples with the
      // same timestamp.
      const a = PositionSample(
          timestampMicros: kT0, tagId: 't1', x: 0, y: 0);
      const b = PositionSample(
          timestampMicros: kT0, tagId: 't1', x: 3, y: 4);

      expect(a.speedTo(b), 0.0);
      expect(a.speedTo(b).isFinite, isTrue);
    });

    test('speed is direction-independent', () {
      const a = PositionSample(
          timestampMicros: kT0, tagId: 't1', x: 0, y: 0);
      const b = PositionSample(
          timestampMicros: kT0 + 1000000, tagId: 't1', x: 6, y: 0);

      expect(a.speedTo(b), closeTo(b.speedTo(a), 1e-12));
    });

    test('preserves microsecond precision across a JSON round trip', () {
      // Integer micros must survive exactly; float seconds would not.
      const s = PositionSample(
        timestampMicros: 1755331200123456,
        tagId: 't1',
        x: 12.3456789,
        y: 7.6543210,
        confidence: 0.87,
      );
      final restored = PositionSample.fromJson(s.toJson());

      expect(restored.timestampMicros, 1755331200123456);
      expect(restored, s);
    });

    test('exposes a UTC DateTime view', () {
      const s = PositionSample(
          timestampMicros: kT0, tagId: 't1', x: 0, y: 0);
      expect(s.timestamp.isUtc, isTrue);
      expect(s.timestamp.microsecondsSinceEpoch, kT0);
    });
  });

  group('PositionFrame', () {
    test('finds the sample for a given tag', () {
      const frame = PositionFrame(timestampMicros: kT0, samples: [
        PositionSample(timestampMicros: kT0, tagId: 't1', x: 1, y: 1),
        PositionSample(timestampMicros: kT0, tagId: 't2', x: 2, y: 2),
      ]);

      expect(frame.sampleForTag('t2')?.x, 2);
      expect(frame.sampleForTag('nope'), isNull);
    });

    test('groups a flat sample list into time-ordered frames', () {
      // Deliberately out of order, as a storage query with a loose sort might
      // return them.
      const samples = [
        PositionSample(timestampMicros: kT0 + 20000, tagId: 't1', x: 3, y: 3),
        PositionSample(timestampMicros: kT0, tagId: 't1', x: 1, y: 1),
        PositionSample(timestampMicros: kT0, tagId: 't2', x: 2, y: 2),
        PositionSample(timestampMicros: kT0 + 20000, tagId: 't2', x: 4, y: 4),
      ];

      final frames = PositionFrame.groupByTimestamp(samples);

      expect(frames, hasLength(2));
      expect(frames[0].timestampMicros, kT0);
      expect(frames[1].timestampMicros, kT0 + 20000);
      expect(frames[0].samples, hasLength(2));
      expect(frames[1].samples, hasLength(2));
      expect(frames[0].tagIds, containsAll(['t1', 't2']));
    });

    test('grouping an empty list yields no frames', () {
      expect(PositionFrame.groupByTimestamp(const []), isEmpty);
    });

    test('survives a JSON round trip', () {
      const frame = PositionFrame(timestampMicros: kT0, samples: [
        PositionSample(timestampMicros: kT0, tagId: 't1', x: 1.5, y: 2.5),
      ]);
      final restored = PositionFrame.fromJson(frame.toJson());

      expect(restored.timestampMicros, kT0);
      expect(restored.samples, frame.samples);
    });
  });
}
