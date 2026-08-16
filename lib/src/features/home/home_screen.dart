import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../domain/court.dart';
import '../court/court_canvas.dart';
import '../court/handball_court_layer.dart';

/// Landing screen: shows the court at true scale and the intended workflow.
class HomeScreen extends StatelessWidget {
  final void Function(AppDestination destination) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final court = Court.handball();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kinetag', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            '${court.name} • ${court.widthMeters.toStringAsFixed(0)} x '
            '${court.heightMeters.toStringAsFixed(0)} m',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CourtCanvas(
                court: court,
                layers: [
                  const CourtSurroundLayer(),
                  HandballCourtLayer(court: court),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => onNavigate(AppDestination.setup),
                icon: const Icon(Icons.settings_input_antenna),
                label: const Text('Set up receivers'),
              ),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AppDestination.live),
                icon: const Icon(Icons.sensors),
                label: const Text('Go live'),
              ),
              OutlinedButton.icon(
                onPressed: () => onNavigate(AppDestination.sessions),
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Recordings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
