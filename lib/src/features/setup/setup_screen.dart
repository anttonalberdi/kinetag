import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../court/court_canvas.dart';
import '../court/handball_court_layer.dart';
import 'receiver_inspector.dart';
import 'receiver_layer.dart';
import 'setup_state.dart';

/// Receiver setup: place the UWB anchors around the court.
///
/// Layout adapts at [_sideInspectorBreakpoint]: a side inspector on wide
/// windows (desktop/tablet landscape), stacked below the court on narrow
/// ones. Both use the same widgets, so there is one implementation to
/// maintain.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  static const double _sideInspectorBreakpoint = 900;
  static const double _inspectorWidth = 300;

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
        _SetupToolbar(
          showGrid: state.showGrid,
          onToggleGrid: controller.setShowGrid,
          onReset: controller.resetLayout,
          receiverCount: state.receivers.length,
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
        final wide = constraints.maxWidth >= _sideInspectorBreakpoint;

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: courtPane),
                const SizedBox(width: 16),
                SizedBox(
                  width: _inspectorWidth,
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: const ReceiverInspector(),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
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
          ),
        );
      },
    );
  }
}

class _SetupToolbar extends StatelessWidget {
  final bool showGrid;
  final ValueChanged<bool> onToggleGrid;
  final VoidCallback onReset;
  final int receiverCount;

  const _SetupToolbar({
    required this.showGrid,
    required this.onToggleGrid,
    required this.onReset,
    required this.receiverCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Wrap rather than Row: on a phone-width window the title and the two
    // controls do not fit on one line, and a Row would overflow.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Setup', style: theme.textTheme.headlineSmall),
            const SizedBox(width: 10),
            Text(
              '$receiverCount receivers',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset layout'),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: showGrid,
              onSelected: onToggleGrid,
              avatar: const Icon(Icons.grid_4x4, size: 18),
              label: const Text('1 m grid'),
            ),
          ],
        ),
      ],
    );
  }
}
