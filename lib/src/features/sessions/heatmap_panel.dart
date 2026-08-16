import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/occupancy_grid.dart';
import '../../analytics/team_metrics.dart';
import '../../core/duration_format.dart';
import '../../core/metric_format.dart';
import '../../domain/domain.dart';
import '../court/court_canvas.dart';
import '../court/court_theme.dart';
import '../court/handball_court_layer.dart';
import '../court/heatmap_layer.dart';
import '../court/tag_roster.dart';
import 'analysis_providers.dart';
import 'replay_controller.dart';
import 'replay_screen.dart';

/// One map a heatmap view can show, and who it belongs to.
///
/// The detail view takes a list of these rather than a single grid so that
/// opening a team's map and comparing it against one player's is a chip away —
/// the grids are already computed, and a map only means something next to
/// another one.
@immutable
class HeatmapSelection {
  final String label;

  /// The colour the map is drawn in — the player's or team's own.
  final Color color;

  /// Unsmoothed dwell times: every figure quoted beside the map is read off
  /// this, so the numbers describe the recording rather than the picture.
  final OccupancyGrid grid;

  /// The end of the court this side defends, when the session recorded one.
  /// Without it there is no such thing as "their own half".
  final TeamSide? side;

  const HeatmapSelection({
    required this.label,
    required this.color,
    required this.grid,
    this.side,
  });
}

/// Height of the inline map on a team card.
const double kTeamHeatmapHeight = 132;

/// Height of the inline map on a player's page, which has the room for more.
const double kPlayerHeatmapHeight = 190;

/// A team's floor map, small, opening the full one when tapped.
///
/// Watches the occupancy itself rather than taking a grid, so a screen can
/// place a heatmap without threading an async value through its layout.
class TeamHeatmapCard extends ConsumerWidget {
  final TeamMetrics team;
  final Color color;
  final double height;

  const TeamHeatmapCard({
    super.key,
    required this.team,
    required this.color,
    this.height = kTeamHeatmapHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(replayRosterProvider);

    return _OccupancyBuilder(
      height: height,
      builder: (court, occupancy) => HeatmapPreview(
        court: court,
        height: height,
        title: '${team.label} • where the time was spent',
        selections: [
          HeatmapSelection(
            label: team.label,
            color: color,
            side: team.side,
            grid: occupancy.forTags([
              for (final track in team.tracks) track.tagId,
            ]),
          ),
          // The players behind the team map, so the reader can ask which of
          // them the shape actually belongs to.
          for (final track in team.tracks)
            HeatmapSelection(
              label: roster.entryFor(track.tagId)?.playerName ?? track.tagId,
              color: roster.entryFor(track.tagId)?.color ??
                  TagRoster.unassignedColor,
              side: team.side,
              grid: occupancy.forTag(track.tagId),
            ),
        ],
      ),
    );
  }
}

/// One player's floor map, small, opening the full one when tapped.
class PlayerHeatmapCard extends ConsumerWidget {
  final String tagId;
  final Color color;

  /// The player's own team, when they have tracked team-mates: their map is
  /// offered beside the player's as the thing to read it against.
  final TeamMetrics? team;

  final double height;

  const PlayerHeatmapCard({
    super.key,
    required this.tagId,
    required this.color,
    required this.team,
    this.height = kPlayerHeatmapHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(replayRosterProvider);
    final name = roster.entryFor(tagId)?.playerName ?? tagId;
    final team = this.team;

    return _OccupancyBuilder(
      height: height,
      builder: (court, occupancy) => HeatmapPreview(
        court: court,
        height: height,
        title: '$name • where the time was spent',
        selections: [
          HeatmapSelection(
            label: name,
            color: color,
            side: team?.side,
            grid: occupancy.forTag(tagId),
          ),
          if (team != null && team.playerCount > 1)
            HeatmapSelection(
              label: team.label,
              color: color,
              side: team.side,
              grid: occupancy.forTags([
                for (final track in team.tracks) track.tagId,
              ]),
            ),
        ],
      ),
    );
  }
}

/// Resolves the open session's court and occupancy, holding the layout steady
/// while they load so that a page does not jump as its maps arrive.
class _OccupancyBuilder extends ConsumerWidget {
  final double height;
  final Widget Function(Court court, SessionOccupancy occupancy) builder;

  const _OccupancyBuilder({required this.height, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final court = ref.watch(
      replayControllerProvider.select((s) => s.session?.court),
    );
    final occupancy = ref.watch(sessionOccupancyProvider);

    return occupancy.when(
      loading: () => _HeatmapPlaceholder(
        height: height,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, _) => _HeatmapPlaceholder(
        height: height,
        child: Text(
          'Could not map this session.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      data: (occupancy) => builder(court ?? Court.handball(), occupancy),
    );
  }
}

/// The small map, and the affordance that says it opens.
class HeatmapPreview extends StatelessWidget {
  final Court court;
  final List<HeatmapSelection> selections;

  /// What the expanded view is called once it is open.
  final String title;

  final double height;

  const HeatmapPreview({
    super.key,
    required this.court,
    required this.selections,
    required this.title,
    this.height = kTeamHeatmapHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = selections.first;

    if (primary.grid.isEmpty) {
      return _HeatmapPlaceholder(
        height: height,
        child: Text(
          'No positions on court were mapped.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Semantics(
      button: true,
      label: '$title, tap to enlarge',
      child: Tooltip(
        message: 'Tap to enlarge',
        child: InkWell(
          onTap: () => showHeatmapDetail(
            context,
            court: court,
            selections: selections,
            title: title,
          ),
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              CourtHeatmap(
                court: court,
                selection: primary,
                height: height,
                showAveragePosition: false,
              ),
              Positioned(
                top: 6,
                right: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The court with one map drawn over it, at whatever size it is given.
class CourtHeatmap extends StatelessWidget {
  final Court court;
  final HeatmapSelection selection;

  /// Null lets the map fill the space it is given; a page that needs the
  /// layout to hold still passes a height.
  final double? height;

  /// Whether the dwell-weighted average position is ringed on the map. Too
  /// fine a mark to read on a thumbnail, so it is off there.
  final bool showAveragePosition;

  const CourtHeatmap({
    super.key,
    required this.court,
    required this.selection,
    this.height,
    this.showAveragePosition = true,
  });

  @override
  Widget build(BuildContext context) {
    final centroid =
        showAveragePosition ? selection.grid.centroidMeters : null;

    final canvas = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CourtCanvas(
        court: court,
        // Just enough surround that the boundary line is not shaved off by
        // the widget's own edge.
        marginMeters: 0.4,
        paddingPixels: 0,
        layers: [
          HandballCourtLayer(court: court, theme: CourtTheme.analysis),
          HeatmapLayer(
            // Smoothed for the picture only: the grid the figures are read
            // from is untouched.
            grid: selection.grid.smoothed(),
            color: selection.color,
          ),
          if (centroid != null)
            AveragePositionLayer(xMeters: centroid.$1, yMeters: centroid.$2),
        ],
      ),
    );

    return height == null ? canvas : SizedBox(height: height, child: canvas);
  }
}

/// A box the size of a map, for when there is no map to draw yet.
class _HeatmapPlaceholder extends StatelessWidget {
  final double height;
  final Widget child;

  const _HeatmapPlaceholder({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

/// Opens the full-size map.
Future<void> showHeatmapDetail(
  BuildContext context, {
  required Court court,
  required List<HeatmapSelection> selections,
  required String title,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => _HeatmapDetailDialog(
        court: court,
        selections: selections,
        title: title,
      ),
    );

/// The map at a size worth reading, with the figures behind it.
///
/// A dialog rather than another page in the breadcrumb trail: this is one
/// figure looked at closely, not a new place in the analysis, and a reader who
/// opens it expects to be back where they were when they close it.
class _HeatmapDetailDialog extends StatefulWidget {
  final Court court;
  final List<HeatmapSelection> selections;
  final String title;

  const _HeatmapDetailDialog({
    required this.court,
    required this.selections,
    required this.title,
  });

  @override
  State<_HeatmapDetailDialog> createState() => _HeatmapDetailDialogState();
}

class _HeatmapDetailDialogState extends State<_HeatmapDetailDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = widget.selections[_index];

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              if (widget.selections.length > 1) ...[
                const SizedBox(height: 4),
                _SelectionChips(
                  selections: widget.selections,
                  index: _index,
                  onChanged: (index) => setState(() => _index = index),
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio:
                            widget.court.widthMeters / widget.court.heightMeters,
                        child: CourtHeatmap(
                          court: widget.court,
                          selection: selection,
                        ),
                      ),
                      const SizedBox(height: 14),
                      HeatmapScaleLegend(selection: selection),
                      const SizedBox(height: 16),
                      _HeatmapFigures(selection: selection),
                      const SizedBox(height: 12),
                      Text(
                        'Each square is '
                        '${selection.grid.cellWidthMeters.toStringAsFixed(1)} × '
                        '${selection.grid.cellHeightMeters.toStringAsFixed(1)} m '
                        'and holds the time spent standing in it, smoothed '
                        'across neighbouring squares so a run reads as a path '
                        'rather than as a row of blocks. Time is credited '
                        'between one fix and the next, and a gap longer than '
                        '${OccupancyGrid.maxAttributableGap.inSeconds}s is '
                        'treated as a dropout rather than as standing still.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionChips extends StatelessWidget {
  final List<HeatmapSelection> selections;
  final int index;
  final ValueChanged<int> onChanged;

  const _SelectionChips({
    required this.selections,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < selections.length; i++)
            ChoiceChip(
              selected: i == index,
              onSelected: (_) => onChanged(i),
              avatar: CircleAvatar(
                backgroundColor: selections[i].color,
                radius: 6,
              ),
              label: Text(selections[i].label),
            ),
        ],
      );
}

/// The key to the colour ramp.
///
/// Deliberately unlabelled at the ends beyond "less" and "more": the ramp is
/// normalised against this map's own busiest square, so the same colour means
/// different amounts of time on two different maps. The amount itself is
/// stated as a figure below, where it cannot be mistaken for a scale that
/// carries between players.
class HeatmapScaleLegend extends StatelessWidget {
  final HeatmapSelection selection;

  /// Steps drawn in the bar. Enough to read as continuous, few enough that
  /// each one is a solid block of colour rather than a gradient artefact.
  static const int _steps = 24;

  const HeatmapScaleLegend({super.key, required this.selection});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          'Less time',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              // On the court's own dark surface, so the ramp's transparency
              // reads here exactly as it does over the floor.
              child: ColoredBox(
                color: CourtTheme.analysis.courtColor,
                child: Row(
                  // Without this the steps take zero height: a childless
                  // `ColoredBox` shrinks to its smallest allowed size, and a
                  // centred row allows zero.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _steps; i++)
                      Expanded(
                        child: ColoredBox(
                          color: heatShade(
                            selection.color,
                            i / (_steps - 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'More',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// What the map amounts to in numbers.
class _HeatmapFigures extends StatelessWidget {
  final HeatmapSelection selection;

  const _HeatmapFigures({required this.selection});

  @override
  Widget build(BuildContext context) {
    final grid = selection.grid;
    final side = selection.side;
    final ownHalf = side == null
        ? null
        : grid.shareWhere(
            (x, _) => side == TeamSide.home
                ? x < grid.widthMeters / 2
                : x >= grid.widthMeters / 2,
          );

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Figure(
          label: 'Time mapped',
          value: formatElapsed(grid.total),
          hint: 'Measured between fixes',
        ),
        _Figure(
          label: 'Busiest square',
          value: formatElapsed(grid.peak),
          hint: 'The single hottest cell',
        ),
        _Figure(
          label: 'Floor covered',
          value: formatShare(grid.coverage),
          hint: 'Squares ever stood in',
        ),
        if (ownHalf != null)
          _Figure(
            label: 'Own half',
            value: formatShare(ownHalf),
            hint: 'Defending the '
                '${side == TeamSide.home ? 'left' : 'right'} goal',
          ),
      ],
    );
  }
}

/// A figure beside the map.
///
/// Narrower than the pages' `StatTile` on purpose: four of these must fit
/// under the map inside a dialog, where a tile built for a full-width page
/// would wrap to two rows.
class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final String hint;

  const _Figure({
    required this.label,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 150,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            hint,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
