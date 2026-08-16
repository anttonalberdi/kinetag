import 'package:flutter/material.dart';

import '../../domain/court.dart';
import '../court/court_canvas.dart';
import '../court/handball_court_layer.dart';

/// Receiver setup.
///
/// This milestone renders the court with a 1 m reference grid so the metre
/// scale can be verified by eye. Selectable and draggable receivers plus the
/// coordinate inspector land in the next increment.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final Court _court = Court.handball();
  bool _showGrid = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Setup', style: theme.textTheme.headlineSmall),
              const Spacer(),
              FilterChip(
                selected: _showGrid,
                onSelected: (v) => setState(() => _showGrid = v),
                avatar: const Icon(Icons.grid_4x4, size: 18),
                label: const Text('1 m grid'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CourtCanvas(
                court: _court,
                layers: [
                  const CourtSurroundLayer(),
                  if (_showGrid) const MetreGridLayer(),
                  HandballCourtLayer(court: _court),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
