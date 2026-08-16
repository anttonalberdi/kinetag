import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/duration_format.dart';
import '../../domain/domain.dart';
import '../court/court_canvas.dart';
import '../court/handball_court_layer.dart';
import '../court/player_layer.dart';
import '../court/tag_roster.dart';
import '../setup/receiver_layer.dart';
import 'replay_controller.dart';

/// Labels and colours for the session being replayed.
///
/// Built from the session's **own** snapshot — the players and tags as they
/// were when the recording was made — not from the current setup. Rebuilt
/// only when the open session changes, so the cached text layouts inside
/// [TagRoster] survive scrubbing and playback.
final replayRosterProvider = Provider<TagRoster>((ref) {
  final session = ref.watch(replayControllerProvider.select((s) => s.session));
  if (session == null) {
    return TagRoster.fromSetup(
      players: const [],
      tags: const [],
      assignments: const [],
    );
  }
  return TagRoster.fromSetup(
    players: session.players,
    tags: session.tags,
    assignments: session.tagAssignments,
  );
});

/// Replays one recorded session on the same canvas the live view uses.
class ReplayScreen extends ConsumerWidget {
  final VoidCallback onBack;

  const ReplayScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading =
        ref.watch(replayControllerProvider.select((s) => s.isLoading));
    final error =
        ref.watch(replayControllerProvider.select((s) => s.errorMessage));
    final session =
        ref.watch(replayControllerProvider.select((s) => s.session));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReplayHeader(session: session, onBack: onBack),
          const SizedBox(height: 12),
          Expanded(
            child: switch ((isLoading, error)) {
              (true, _) => const Center(child: CircularProgressIndicator()),
              (_, final String message) => _ReplayMessage(message: message),
              _ => const _ReplayCourt(),
            },
          ),
          const SizedBox(height: 12),
          const _ReplayTransport(),
        ],
      ),
    );
  }
}

class _ReplayHeader extends StatelessWidget {
  final Session? session;
  final VoidCallback onBack;

  const _ReplayHeader({required this.session, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to sessions',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                session?.name ?? 'Replay',
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
              if (session != null)
                Text(
                  '${session!.players.length} players • '
                  '${session!.sampleCount} samples',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReplayMessage extends StatelessWidget {
  final String message;

  const _ReplayMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge
            ?.copyWith(color: theme.colorScheme.error),
      ),
    );
  }
}

/// The court, redrawn per replayed frame — the same widget stack the live
/// view builds, fed from storage instead of from the hub.
class _ReplayCourt extends ConsumerWidget {
  const _ReplayCourt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(replayControllerProvider.select((s) => s.session));
    final frame = ref.watch(replayControllerProvider.select((s) => s.frame));
    final roster = ref.watch(replayRosterProvider);

    // The court and receivers come from the session's frozen setup: a
    // recording must always be shown against the geometry that produced it.
    final court = session?.court ?? Court.handball();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CourtCanvas(
        court: court,
        layers: [
          const CourtSurroundLayer(),
          HandballCourtLayer(court: court),
          ReceiverLayer(receivers: session?.receivers ?? const []),
          PlayerLayer(frame: frame, roster: roster),
        ],
      ),
    );
  }
}

/// Play/pause, frame stepping, the timeline scrubber and playback speed.
class _ReplayTransport extends ConsumerWidget {
  const _ReplayTransport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(replayControllerProvider);
    final controller = ref.read(replayControllerProvider.notifier);
    final enabled = state.hasRecording;

    return Column(
      children: [
        Row(
          children: [
            Text(
              formatElapsed(state.position),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: Slider(
                value: state.progress,
                // Seeking is by position, so dragging backwards is exactly as
                // cheap as dragging forwards.
                onChanged: enabled ? controller.seekToProgress : null,
              ),
            ),
            Text(
              formatElapsed(state.duration),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 8,
          children: [
            IconButton(
              onPressed: enabled ? () => controller.seek(Duration.zero) : null,
              icon: const Icon(Icons.skip_previous),
              tooltip: 'Back to start',
            ),
            IconButton(
              onPressed:
                  enabled ? () => controller.step(forward: false) : null,
              icon: const Icon(Icons.fast_rewind),
              tooltip: 'Previous frame',
            ),
            FilledButton.icon(
              onPressed: enabled ? controller.togglePlay : null,
              icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(state.isPlaying ? 'Pause' : 'Play'),
            ),
            IconButton(
              onPressed: enabled ? () => controller.step(forward: true) : null,
              icon: const Icon(Icons.fast_forward),
              tooltip: 'Next frame',
            ),
            const SizedBox(width: 8),
            DropdownButton<double>(
              value: state.speed,
              onChanged: enabled
                  ? (speed) {
                      if (speed != null) controller.setSpeed(speed);
                    }
                  : null,
              items: [
                for (final speed in kPlaybackSpeeds)
                  DropdownMenuItem(
                    value: speed,
                    child: Text('${_speedLabel(speed)}x'),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Text(
              '${state.frameCount} frames',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  static String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : '$speed';
}
