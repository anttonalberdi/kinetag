import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'coordinate_field.dart';
import 'setup_state.dart';

/// Inspector for the selected receiver: precise coordinates plus the derived
/// distances to every other receiver.
///
/// Dragging is deliberately approximate; this panel is where exact placement
/// happens, which matters because anchor geometry directly limits positioning
/// accuracy.
class ReceiverInspector extends ConsumerWidget {
  const ReceiverInspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);
    final receiver = state.selectedReceiver;

    if (receiver == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 36, color: theme.colorScheme.outline),
              const SizedBox(height: 10),
              Text('No receiver selected',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Click a receiver on the court to inspect and position it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final distances = state.distancesFromSelection;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.settings_input_antenna,
                color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(receiver.name, style: theme.textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 16),
        CoordinateField(
          key: ValueKey('x-${receiver.id}'),
          label: 'X',
          value: receiver.x,
          onChanged: (v) => controller.moveReceiver(receiver.id, x: v),
        ),
        const SizedBox(height: 10),
        CoordinateField(
          key: ValueKey('y-${receiver.id}'),
          label: 'Y',
          value: receiver.y,
          onChanged: (v) => controller.moveReceiver(receiver.id, y: v),
        ),
        const SizedBox(height: 10),
        CoordinateField(
          key: ValueKey('z-${receiver.id}'),
          label: 'Height',
          value: receiver.z,
          onChanged: (v) => controller.moveReceiver(receiver.id, z: v),
        ),
        const SizedBox(height: 20),
        Text('Distances', style: theme.textTheme.titleSmall),
        Text(
          'Straight-line, including height difference',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (final entry in distances)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.receiver.name, style: theme.textTheme.bodyMedium),
                Text(
                  '${entry.distanceMeters.toStringAsFixed(2)} m',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
