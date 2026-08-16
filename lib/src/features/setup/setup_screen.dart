import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../court/court_canvas.dart';
import '../court/handball_court_layer.dart';
import '../live/live_controller.dart';
import 'receiver_inspector.dart';
import 'receiver_layer.dart';
import 'roster_panel.dart';
import 'setup_state.dart';

/// The two halves of setting a session up.
enum SetupSection {
  receivers('Receivers', Icons.settings_input_antenna),
  players('Players', Icons.groups_outlined);

  const SetupSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Session setup: place the UWB anchors, then declare who is wearing a tag.
///
/// The two sections are separate because they use the screen completely
/// differently — anchor placement is spatial and needs the whole court canvas,
/// while the roster is a list of records — and because an operator does them
/// at different times: anchors once per hall, the roster once per session.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  static const double _sideInspectorBreakpoint = 900;
  static const double _inspectorWidth = 300;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  SetupSection _section = SetupSection.receivers;

  @override
  Widget build(BuildContext context) {
    final isRecording = ref.watch(recordingInProgressProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SetupHeader(
            section: _section,
            onSectionChanged: (s) => setState(() => _section = s),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (_section) {
              SetupSection.receivers => const _ReceiverSection(),
              SetupSection.players => Card(
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: RosterPanel(locked: isRecording),
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _SetupHeader extends StatelessWidget {
  final SetupSection section;
  final ValueChanged<SetupSection> onSectionChanged;

  const _SetupHeader({required this.section, required this.onSectionChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Wrap rather than Row: on a phone-width window the title and the section
    // switch do not fit on one line, and a Row would overflow.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text('Setup', style: theme.textTheme.headlineSmall),
        SegmentedButton<SetupSection>(
          segments: [
            for (final s in SetupSection.values)
              ButtonSegment(
                value: s,
                label: Text(s.label),
                icon: Icon(s.icon, size: 18),
              ),
          ],
          selected: {section},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onSectionChanged(selection.first),
        ),
      ],
    );
  }
}

/// Anchor placement: the court canvas plus the coordinate inspector.
///
/// Layout adapts at [SetupScreen._sideInspectorBreakpoint]: a side inspector
/// on wide windows (desktop/tablet landscape), stacked below the court on
/// narrow ones. Both use the same widgets, so there is one implementation to
/// maintain.
class _ReceiverSection extends ConsumerWidget {
  const _ReceiverSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    final court = CourtCanvas(
      court: state.court,
      layers: [
        const CourtSurroundLayer(),
        if (state.showGrid) const MetreGridLayer(),
        HandballCourtLayer(court: state.court),
        ReceiverBaselineLayer(
          receivers: state.receivers,
          selectedReceiverId: state.selectedReceiverId,
        ),
        ReceiverLayer(
          receivers: state.receivers,
          selectedReceiverId: state.selectedReceiverId,
        ),
      ],
      // A fingertip/cursor target is a fixed pixel size, so the world-space
      // tolerance is derived from the current scale on every interaction.
      onWorldTapDown: (world, transform) => controller.selectAt(
        world,
        transform.pixelsToMetres(ReceiverLayer.hitRadiusPixels),
      ),
      onWorldPanStart: (pointerDown, transform) => controller.beginDrag(
        pointerDown,
        transform.pixelsToMetres(ReceiverLayer.hitRadiusPixels),
      ),
      onWorldPanUpdate: (world, transform) => controller.updateDrag(
        SetupController.clampToVisibleWorld(world, transform.visibleWorld),
      ),
      onWorldPanEnd: controller.endDrag,
    );

    final courtPane = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReceiverToolbar(
          showGrid: state.showGrid,
          onToggleGrid: controller.setShowGrid,
          onReset: controller.resetLayout,
          receiverCount: state.receiverCount,
          layoutShape: state.layoutShape,
          onCountChanged: controller.setReceiverCount,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: court,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= SetupScreen._sideInspectorBreakpoint;

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: courtPane),
              const SizedBox(width: 16),
              SizedBox(
                width: SetupScreen._inspectorWidth,
                child: Card(
                  margin: EdgeInsets.zero,
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: const ReceiverInspector(),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 3, child: courtPane),
            const SizedBox(height: 12),
            Expanded(
              flex: 2,
              child: Card(
                margin: EdgeInsets.zero,
                color: theme.colorScheme.surfaceContainerHigh,
                child: const ReceiverInspector(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReceiverToolbar extends StatelessWidget {
  final bool showGrid;
  final ValueChanged<bool> onToggleGrid;
  final VoidCallback onReset;
  final int receiverCount;
  final ReceiverLayoutShape layoutShape;
  final ValueChanged<int> onCountChanged;

  const _ReceiverToolbar({
    required this.showGrid,
    required this.onToggleGrid,
    required this.onReset,
    required this.receiverCount,
    required this.layoutShape,
    required this.onCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    // Nested `Wrap`s throughout: on a phone-width window neither the count
    // selector nor the two view controls fit beside the title, and a `Row`
    // would overflow rather than reflow.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Text('Receivers', style: theme.textTheme.titleMedium),
                SegmentedButton<int>(
                  segments: [
                    for (var n = minReceiverCount; n <= maxReceiverCount; n++)
                      ButtonSegment(value: n, label: Text('$n')),
                  ],
                  selected: {receiverCount},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      onCountChanged(selection.first),
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset layout'),
                ),
                FilterChip(
                  selected: showGrid,
                  onSelected: onToggleGrid,
                  avatar: const Icon(Icons.grid_4x4, size: 18),
                  label: const Text('1 m grid'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${layoutShape.displayName} layout — changing the count re-applies '
          'it',
          style: muted,
        ),
      ],
    );
  }
}
