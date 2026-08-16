import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/analytics_thresholds.dart';
import 'package:kinetag/src/analytics/occupancy_grid.dart';
import 'package:kinetag/src/domain/domain.dart';

const int kStartMicros = 1786000000000000;

final Court kCourt = Court.handball();

/// Samples for one tag standing still at `(x, y)`, one per [stepMicros].
///
/// [count] samples span `count - 1` intervals, which is the time the grid can
/// actually account for.
List<PositionSample> standingAt(
  double x,
  double y, {
  String tagId = 'tag-1',
  int count = 11,
  int stepMicros = 100000,
  int firstMicros = kStartMicros,
  double confidence = 1.0,
}) =>
    [
      for (var i = 0; i < count; i++)
        PositionSample(
          timestampMicros: firstMicros + i * stepMicros,
          tagId: tagId,
          x: x,
          y: y,
          confidence: confidence,
        ),
    ];

void main() {
  group('grid shape', () {
    test('covers the playing area exactly at the requested cell size', () {
      final grid = OccupancyGrid.empty(court: kCourt, cellSizeMeters: 0.5);

      expect(grid.columns, 80);
      expect(grid.rows, 40);
      expect(grid.cellWidthMeters, 0.5);
      expect(grid.cellHeightMeters, 0.5);
      expect(grid.cellCount, 3200);
      expect(grid.isEmpty, isTrue);
    });

    test('keeps at least one cell for a court smaller than a cell', () {
      final grid = OccupancyGrid.empty(
        court: kCourt.copyWith(widthMeters: 0.2, heightMeters: 0.2),
        cellSizeMeters: 1.0,
      );

      expect(grid.columns, 1);
      expect(grid.rows, 1);
    });
  });

  group('accumulation', () {
    test('credits elapsed time, not sample count, to the cell stood in', () {
      final grid = OccupancyGrid.fromTrack(
        standingAt(10.25, 5.25),
        court: kCourt,
      );

      // Ten intervals of 100 ms between eleven samples.
      expect(grid.total, const Duration(seconds: 1));
      expect(grid.dwellAt(20, 10), const Duration(seconds: 1));
      expect(grid.peak, const Duration(seconds: 1));
    });

    test('a slower-reporting tag standing as long measures the same', () {
      final fast = OccupancyGrid.fromTrack(
        standingAt(10.25, 5.25, count: 21, stepMicros: 100000),
        court: kCourt,
      );
      final slow = OccupancyGrid.fromTrack(
        standingAt(10.25, 5.25, count: 5, stepMicros: 500000),
        court: kCourt,
      );

      expect(fast.total, const Duration(seconds: 2));
      expect(slow.total, const Duration(seconds: 2));
    });

    test('caps a dropout instead of crediting it to the last cell seen', () {
      final grid = OccupancyGrid.fromTrack(
        [
          PositionSample(
            timestampMicros: kStartMicros,
            tagId: 'tag-1',
            x: 10.25,
            y: 5.25,
          ),
          // A minute of silence, then the tag reappears.
          PositionSample(
            timestampMicros: kStartMicros + 60 * 1000000,
            tagId: 'tag-1',
            x: 10.25,
            y: 5.25,
          ),
        ],
        court: kCourt,
      );

      expect(grid.total, OccupancyGrid.maxAttributableGap);
    });

    test('sorts an out-of-order track before crediting intervals', () {
      final ordered = standingAt(10.25, 5.25);
      final grid = OccupancyGrid.fromTrack(
        ordered.reversed,
        court: kCourt,
      );

      expect(grid.total, const Duration(seconds: 1));
    });

    test('pulls a fix just outside the lines onto the nearest cell', () {
      final grid = OccupancyGrid.fromTrack(
        standingAt(-0.4, 10.0),
        court: kCourt,
      );

      expect(grid.dwellAt(0, 20), const Duration(seconds: 1));
    });

    test('drops a fix too far out to be play, rather than piling it on the '
        'sideline', () {
      final grid = OccupancyGrid.fromTrack(
        standingAt(10.0, -3.0),
        court: kCourt,
      );

      expect(grid.isEmpty, isTrue);
      expect(grid.total, Duration.zero);
    });
  });

  group('summaries', () {
    test('coverage counts the cells ever stood in', () {
      final grid = OccupancyGrid.fromTrack(
        [
          ...standingAt(1.25, 1.25, count: 3),
          ...standingAt(
            30.25,
            15.25,
            count: 3,
            firstMicros: kStartMicros + 10 * 1000000,
          ),
        ],
        court: kCourt,
      );

      // Two cells of 3200: the interval that bridges the two spots is
      // credited to the one the player left, not to a third place.
      expect(grid.coverage, closeTo(2 / 3200, 1e-9));
    });

    test('the centroid weighs where the time went, not where the fixes were',
        () {
      final grid = OccupancyGrid.fromTrack(
        [
          // Nine seconds on the left wing, one second on the right.
          ...standingAt(2.25, 10.25, count: 91),
          ...standingAt(
            38.25,
            10.25,
            count: 11,
            firstMicros: kStartMicros + 30 * 1000000,
          ),
        ],
        court: kCourt,
      );

      final centroid = grid.centroidMeters;
      expect(centroid, isNotNull);
      // Well inside the left half despite the two spots being symmetric.
      expect(centroid!.$1, lessThan(10));
      expect(centroid.$2, closeTo(10.25, 0.5));
    });

    test('an empty grid has no centroid', () {
      expect(OccupancyGrid.empty(court: kCourt).centroidMeters, isNull);
    });

    test('shareWhere splits the mapped time by a region of the court', () {
      final grid = OccupancyGrid.fromTrack(
        [
          ...standingAt(5.25, 10.25, count: 31),
          ...standingAt(
            35.25,
            10.25,
            count: 11,
            firstMicros: kStartMicros + 30 * 1000000,
          ),
        ],
        court: kCourt,
      );

      // Five seconds are measured in all: three standing left, one standing
      // right, and the capped interval between the two, which is credited to
      // the left where it started.
      expect(grid.total, const Duration(seconds: 5));
      expect(grid.shareWhere((x, _) => x < 20), closeTo(0.8, 0.01));
      expect(grid.shareWhere((x, _) => x >= 20), closeTo(0.2, 0.01));
    });
  });

  group('merging', () {
    test('a team grid is the sum of its players', () {
      final one = OccupancyGrid.fromTrack(standingAt(10.25, 5.25), court: kCourt);
      final two = OccupancyGrid.fromTrack(standingAt(10.25, 5.25), court: kCourt);
      final three =
          OccupancyGrid.fromTrack(standingAt(30.25, 5.25), court: kCourt);

      final merged = OccupancyGrid.merged([one, two, three]);

      expect(merged.dwellAt(20, 10), const Duration(seconds: 2));
      expect(merged.dwellAt(60, 10), const Duration(seconds: 1));
      expect(merged.total, const Duration(seconds: 3));
    });

    test('merging nothing is a programming error, not an empty grid', () {
      expect(() => OccupancyGrid.merged([]), throwsArgumentError);
    });
  });

  group('smoothing', () {
    test('spreads a single hot cell over its neighbours', () {
      final grid =
          OccupancyGrid.fromTrack(standingAt(10.25, 5.25), court: kCourt)
              .smoothed();

      expect(grid.dwellAt(20, 10).inMicroseconds, greaterThan(0));
      expect(grid.dwellAt(19, 10).inMicroseconds, greaterThan(0));
      expect(grid.dwellAt(21, 11).inMicroseconds, greaterThan(0));
      // Beyond the kernel nothing is invented.
      expect(grid.dwellAt(23, 10), Duration.zero);
    });

    test('keeps the total it was given, to rounding', () {
      final raw = OccupancyGrid.fromTrack(
        [
          for (var i = 0; i < 200; i++)
            PositionSample(
              timestampMicros: kStartMicros + i * 100000,
              tagId: 'tag-1',
              x: 5 + i * 0.1,
              y: 8 + (i % 20) * 0.2,
            ),
        ],
        court: kCourt,
      );

      final smoothed = raw.smoothed();

      expect(
        smoothed.total.inMicroseconds,
        closeTo(raw.total.inMicroseconds, raw.total.inMicroseconds * 0.02),
      );
      expect(smoothed.peak.inMicroseconds, lessThan(raw.peak.inMicroseconds));
    });

    test('leaves an empty grid alone', () {
      final empty = OccupancyGrid.empty(court: kCourt);
      expect(identical(empty.smoothed(), empty), isTrue);
    });
  });

  group('SessionOccupancy', () {
    test('builds one grid per tag and a combined map that is their sum', () {
      final occupancy = SessionOccupancy.fromSamples(
        [
          ...standingAt(10.25, 5.25, tagId: 'tag-a'),
          ...standingAt(30.25, 15.25, tagId: 'tag-b'),
        ],
        court: kCourt,
      );

      expect(occupancy.byTagId.keys, containsAll(['tag-a', 'tag-b']));
      expect(occupancy.forTag('tag-a').total, const Duration(seconds: 1));
      expect(occupancy.combined.total, const Duration(seconds: 2));
      expect(occupancy.combined.dwellAt(20, 10), const Duration(seconds: 1));
      expect(occupancy.combined.dwellAt(60, 30), const Duration(seconds: 1));
    });

    test('a subset of tags adds up to exactly those players', () {
      final occupancy = SessionOccupancy.fromSamples(
        [
          ...standingAt(10.25, 5.25, tagId: 'tag-a'),
          ...standingAt(10.25, 5.25, tagId: 'tag-b'),
          ...standingAt(30.25, 15.25, tagId: 'tag-c'),
        ],
        court: kCourt,
      );

      final pair = occupancy.forTags(['tag-a', 'tag-b']);

      expect(pair.total, const Duration(seconds: 2));
      expect(pair.dwellAt(60, 30), Duration.zero);
    });

    test('an unknown tag maps to an empty grid of the same shape', () {
      final occupancy = SessionOccupancy.fromSamples(
        standingAt(10.25, 5.25, tagId: 'tag-a'),
        court: kCourt,
      );

      final unknown = occupancy.forTag('tag-z');

      expect(unknown.isEmpty, isTrue);
      expect(unknown.columns, occupancy.combined.columns);
      expect(unknown.rows, occupancy.combined.rows);
      expect(occupancy.forTags(const []).isEmpty, isTrue);
    });

    test('drops samples below the confidence threshold', () {
      final occupancy = SessionOccupancy.fromSamples(
        [
          ...standingAt(10.25, 5.25, tagId: 'tag-a', confidence: 0.2),
          ...standingAt(30.25, 15.25, tagId: 'tag-b', confidence: 0.9),
        ],
        court: kCourt,
        thresholds: const AnalyticsThresholds(minConfidence: 0.5),
      );

      expect(occupancy.byTagId.keys, ['tag-b']);
      expect(occupancy.combined.total, const Duration(seconds: 1));
    });

    test('a session with nothing usable is empty rather than absent', () {
      final occupancy = SessionOccupancy.fromSamples(const [], court: kCourt);

      expect(occupancy.isEmpty, isTrue);
      expect(occupancy.combined.columns, 80);
    });
  });
}
