import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../domain/domain.dart';
import 'analytics_thresholds.dart';

/// How long a tag spent in each cell of a grid laid over the playing area.
///
/// Derived, never stored, for the same reason the rest of `analytics/` is: the
/// samples are the single source of truth, and a stored grid would freeze both
/// the cell size and the noise rules it was built under.
///
/// The grid always covers the playing area exactly — `(0,0)` to
/// `(widthMeters, heightMeters)` — so a cell index means the same thing to the
/// arithmetic here and to a painter drawing over the court.
@immutable
class OccupancyGrid {
  /// Cells along X and along Y. Together with the extent they fix the cell
  /// size, so a grid always knows the ground it covers.
  final int columns;
  final int rows;

  final double widthMeters;
  final double heightMeters;

  /// Dwell time per cell in microseconds, row-major: cell `(col, row)` lives
  /// at `row * columns + col`.
  ///
  /// A packed list rather than a map of points: a handball court at the
  /// default cell size is 3200 cells, every one of them read on every paint,
  /// and a map lookup per cell per frame is the kind of cost that only shows
  /// up once someone opens a session with twelve players in it.
  final List<int> dwellMicros;

  const OccupancyGrid({
    required this.columns,
    required this.rows,
    required this.widthMeters,
    required this.heightMeters,
    required this.dwellMicros,
  })  : assert(columns > 0 && rows > 0),
        assert(dwellMicros.length == columns * rows);

  /// Default cell edge in metres.
  ///
  /// Half a metre is about the width of a standing player: finer than that and
  /// a cell is measuring positioning noise rather than where someone stood,
  /// coarser and a wing's whole working area collapses into two cells.
  static const double defaultCellSizeMeters = 0.5;

  /// A gap longer than this is a dropout, not time spent standing still.
  ///
  /// Same reasoning — and the same value — as
  /// `SpeedZoneBreakdown.maxAttributableGap`: without the cap, a tag that goes
  /// silent for a minute would paint that whole minute onto whichever cell it
  /// was last seen in, which is the one artefact a heatmap reader cannot spot.
  static const Duration maxAttributableGap = Duration(seconds: 1);

  /// How far outside the lines a fix is still credited to the court.
  ///
  /// Play genuinely happens on and just past the line — a throw-in, a wing
  /// taking off from the corner — and positioning error puts more of it there.
  /// Those fixes are pulled to the nearest cell. Anything further out is a
  /// player on the bench or a bad fix, and is dropped rather than piled onto
  /// the sideline as a false hot spot.
  static const double outOfBoundsToleranceMeters = 1.0;

  /// An all-zero grid covering [court], for a player with nothing to show.
  factory OccupancyGrid.empty({
    required Court court,
    double cellSizeMeters = defaultCellSizeMeters,
  }) {
    final columns = _cellCount(court.widthMeters, cellSizeMeters);
    final rows = _cellCount(court.heightMeters, cellSizeMeters);
    return OccupancyGrid(
      columns: columns,
      rows: rows,
      widthMeters: court.widthMeters,
      heightMeters: court.heightMeters,
      dwellMicros: List<int>.filled(columns * rows, 0),
    );
  }

  /// Accumulates one tag's samples into a grid.
  ///
  /// Each interval between consecutive samples is credited to the cell the
  /// player was in when it *started*, capped at [maxAttributableGap]. Crediting
  /// elapsed time rather than counting samples is what makes two players
  /// comparable when their tags report at different rates.
  factory OccupancyGrid.fromTrack(
    Iterable<PositionSample> track, {
    required Court court,
    double cellSizeMeters = defaultCellSizeMeters,
  }) {
    final grid = OccupancyGrid.empty(court: court, cellSizeMeters: cellSizeMeters);
    final samples = track.toList()
      ..sort((a, b) => a.timestampMicros.compareTo(b.timestampMicros));

    final capMicros = maxAttributableGap.inMicroseconds;
    for (var i = 1; i < samples.length; i++) {
      final gap = samples[i].timestampMicros - samples[i - 1].timestampMicros;
      if (gap <= 0) continue;

      final cell = grid._cellFor(samples[i - 1].x, samples[i - 1].y);
      if (cell == null) continue;

      grid.dwellMicros[cell] += gap > capMicros ? capMicros : gap;
    }

    return grid;
  }

  /// Several players' grids added together, for a team map.
  ///
  /// Every part must cover the same ground at the same resolution — they are
  /// all built from one session's court, so a mismatch is a programming error
  /// rather than something a caller could recover from.
  factory OccupancyGrid.merged(Iterable<OccupancyGrid> parts) {
    final list = parts.toList();
    if (list.isEmpty) {
      throw ArgumentError.value(parts, 'parts', 'cannot merge nothing');
    }

    final first = list.first;
    final summed = List<int>.filled(first.dwellMicros.length, 0);
    for (final part in list) {
      assert(
        part.columns == first.columns && part.rows == first.rows,
        'grids of different shapes cannot be merged',
      );
      for (var i = 0; i < summed.length; i++) {
        summed[i] += part.dwellMicros[i];
      }
    }

    return OccupancyGrid(
      columns: first.columns,
      rows: first.rows,
      widthMeters: first.widthMeters,
      heightMeters: first.heightMeters,
      dwellMicros: summed,
    );
  }

  double get cellWidthMeters => widthMeters / columns;

  double get cellHeightMeters => heightMeters / rows;

  int get cellCount => dwellMicros.length;

  int dwellMicrosAt(int column, int row) =>
      dwellMicros[row * columns + column];

  Duration dwellAt(int column, int row) =>
      Duration(microseconds: dwellMicrosAt(column, row));

  /// Total time this grid accounts for — the sum of every cell.
  Duration get total =>
      Duration(microseconds: dwellMicros.fold(0, (sum, value) => sum + value));

  /// The busiest single cell, which is what a heatmap's colour scale is
  /// normalised against.
  Duration get peak => Duration(
        microseconds: dwellMicros.fold(0, math.max),
      );

  bool get isEmpty => peak == Duration.zero;

  /// Fraction of the court's cells the player was ever measured in, in 0..1 —
  /// a one-number answer to "did they work a corner or the whole floor".
  double get coverage {
    if (cellCount == 0) return 0;
    var visited = 0;
    for (final value in dwellMicros) {
      if (value > 0) visited++;
    }
    return visited / cellCount;
  }

  /// Dwell-weighted mean position in metres, or null for an empty grid.
  ///
  /// The average of where the time was spent, not of where the samples were:
  /// a player who stood on the wing for ten minutes and crossed the court once
  /// averages out on the wing.
  (double x, double y)? get centroidMeters {
    var weight = 0.0;
    var x = 0.0;
    var y = 0.0;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final value = dwellMicros[row * columns + column].toDouble();
        if (value <= 0) continue;
        weight += value;
        x += value * ((column + 0.5) * cellWidthMeters);
        y += value * ((row + 0.5) * cellHeightMeters);
      }
    }

    return weight <= 0 ? null : (x / weight, y / weight);
  }

  /// Share of the mapped time spent where [test] holds, in 0..1.
  ///
  /// [test] receives the centre of each cell in metres, which is what lets a
  /// caller ask about a half, a third or a goal area without this class having
  /// to know what any of those are.
  double shareWhere(bool Function(double xMeters, double yMeters) test) {
    var matched = 0;
    var all = 0;

    for (var row = 0; row < rows; row++) {
      final y = (row + 0.5) * cellHeightMeters;
      for (var column = 0; column < columns; column++) {
        final value = dwellMicros[row * columns + column];
        if (value <= 0) continue;
        all += value;
        if (test((column + 0.5) * cellWidthMeters, y)) matched += value;
      }
    }

    return all <= 0 ? 0 : matched / all;
  }

  /// This cell's share of the busiest cell, in 0..1 — the value a sequential
  /// colour ramp is read from.
  double intensityAt(int column, int row) {
    final peakMicros = peak.inMicroseconds;
    if (peakMicros <= 0) return 0;
    return dwellMicrosAt(column, row) / peakMicros;
  }

  /// A blurred copy, for display.
  ///
  /// Presentation, not measurement: real movement is continuous, and drawing
  /// raw cells makes a smooth run across the court look like a row of separate
  /// squares. A box blur of [radius] cells is applied along each axis in turn,
  /// with the edges extended so that the corners of the court do not fade out
  /// for want of neighbours. The total is preserved to rounding, and no cell
  /// gains time the player did not spend nearby.
  OccupancyGrid smoothed({int radius = 1}) {
    if (radius <= 0 || isEmpty) return this;

    final horizontal = List<double>.filled(cellCount, 0);
    final window = radius * 2 + 1;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        var sum = 0.0;
        for (var offset = -radius; offset <= radius; offset++) {
          final source = (column + offset).clamp(0, columns - 1);
          sum += dwellMicros[row * columns + source];
        }
        horizontal[row * columns + column] = sum / window;
      }
    }

    final blurred = List<int>.filled(cellCount, 0);
    for (var column = 0; column < columns; column++) {
      for (var row = 0; row < rows; row++) {
        var sum = 0.0;
        for (var offset = -radius; offset <= radius; offset++) {
          final source = (row + offset).clamp(0, rows - 1);
          sum += horizontal[source * columns + column];
        }
        blurred[row * columns + column] = (sum / window).round();
      }
    }

    return OccupancyGrid(
      columns: columns,
      rows: rows,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      dwellMicros: blurred,
    );
  }

  /// The cell a position belongs to, or null when it is too far off court to
  /// be play — see [outOfBoundsToleranceMeters].
  int? _cellFor(double xMeters, double yMeters) {
    const tolerance = outOfBoundsToleranceMeters;
    if (xMeters < -tolerance || xMeters > widthMeters + tolerance) return null;
    if (yMeters < -tolerance || yMeters > heightMeters + tolerance) return null;

    final column = (xMeters / cellWidthMeters).floor().clamp(0, columns - 1);
    final row = (yMeters / cellHeightMeters).floor().clamp(0, rows - 1);
    return row * columns + column;
  }

  static int _cellCount(double extentMeters, double cellSizeMeters) =>
      math.max(1, (extentMeters / cellSizeMeters).round());

  @override
  String toString() => 'OccupancyGrid(${columns}x$rows over '
      '${widthMeters}x${heightMeters}m, ${total.inSeconds}s mapped)';
}

/// Every tracked tag's occupancy for one recording, plus the combined map.
///
/// Pure Dart like `SessionMetrics`, and grouped the same way: one grid per tag,
/// with team and session maps built by adding those grids up rather than by
/// measuring anything separately. A team map is therefore always exactly the
/// sum of the player maps a coach can open beside it.
@immutable
class SessionOccupancy {
  final Map<String, OccupancyGrid> byTagId;

  /// Every tracked tag added together.
  final OccupancyGrid combined;

  /// The rules these grids were built under, carried for the same reason
  /// `SessionMetrics` carries them.
  final AnalyticsThresholds thresholds;

  const SessionOccupancy({
    required this.byTagId,
    required this.combined,
    this.thresholds = AnalyticsThresholds.defaults,
  });

  /// An occupancy with nothing in it, shaped to [court].
  factory SessionOccupancy.empty({
    required Court court,
    AnalyticsThresholds thresholds = AnalyticsThresholds.defaults,
    double cellSizeMeters = OccupancyGrid.defaultCellSizeMeters,
  }) =>
      SessionOccupancy(
        byTagId: const {},
        combined:
            OccupancyGrid.empty(court: court, cellSizeMeters: cellSizeMeters),
        thresholds: thresholds,
      );

  /// Builds one grid per tag from a flat list of samples.
  ///
  /// Only the confidence filter applies here, not the speed ceiling that
  /// `SessionMetrics` uses to protect a distance total: a single bad fix can
  /// add tens of metres to a distance, but it can only ever add one sample
  /// interval of dwell to one cell, which the blur and the colour scale swallow.
  factory SessionOccupancy.fromSamples(
    Iterable<PositionSample> samples, {
    required Court court,
    AnalyticsThresholds thresholds = AnalyticsThresholds.defaults,
    double cellSizeMeters = OccupancyGrid.defaultCellSizeMeters,
  }) {
    final byTag = <String, List<PositionSample>>{};
    for (final sample in samples) {
      if (sample.confidence < thresholds.minConfidence) continue;
      (byTag[sample.tagId] ??= []).add(sample);
    }

    final grids = {
      for (final entry in byTag.entries)
        entry.key: OccupancyGrid.fromTrack(
          entry.value,
          court: court,
          cellSizeMeters: cellSizeMeters,
        ),
    };

    return SessionOccupancy(
      byTagId: grids,
      combined: grids.isEmpty
          ? OccupancyGrid.empty(court: court, cellSizeMeters: cellSizeMeters)
          : OccupancyGrid.merged(grids.values),
      thresholds: thresholds,
    );
  }

  bool get isEmpty => combined.isEmpty;

  /// One tag's map, or an empty one for a tag with no usable samples, so a
  /// caller never has to decide what to draw for a player who was not tracked.
  OccupancyGrid forTag(String tagId) => byTagId[tagId] ?? _emptyLikeCombined();

  /// The maps of several tags added together — a team, a line, a pairing.
  OccupancyGrid forTags(Iterable<String> tagIds) {
    final grids = [
      for (final tagId in tagIds) ?byTagId[tagId],
    ];
    return grids.isEmpty ? _emptyLikeCombined() : OccupancyGrid.merged(grids);
  }

  OccupancyGrid _emptyLikeCombined() => OccupancyGrid(
        columns: combined.columns,
        rows: combined.rows,
        widthMeters: combined.widthMeters,
        heightMeters: combined.heightMeters,
        dwellMicros: List<int>.filled(combined.cellCount, 0),
      );
}
