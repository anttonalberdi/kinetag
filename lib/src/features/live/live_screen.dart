import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/duration_format.dart';
import '../../tracking/tracking_message.dart';
import '../court/court_canvas.dart';
import '../court/handball_court_layer.dart';
import '../court/player_layer.dart';
import '../setup/receiver_layer.dart';
import '../setup/setup_state.dart';
import 'live_controller.dart';
import 'live_roster.dart';

/// Live tracking: the court, the tags moving on it, and recording controls.
///
/// The screen is split into small consumers that each watch one slice of
/// [LiveState]. That is not tidiness for its own sake: frames arrive at 20 Hz
/// today and 50–100 Hz with real hardware, and a single widget watching the
/// whole state would rebuild the toolbar, the buttons and the clock at that
/// rate. Only [_LiveCourt] rebuilds per frame; the clock rebuilds once a
/// second because it watches whole seconds, not durations.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  @override
  void initState() {
    super.initState();
    // Connect on first open rather than at app start, so the simulator only
    // runs when someone is looking at it. Deferred by a microtask because
    // provider state must not be mutated during the first build.
    Future.microtask(() {
      if (mounted) ref.read(liveControllerProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _LiveHeader(),
          SizedBox(height: 12),
          Expanded(child: _LiveCourt()),
          SizedBox(height: 12),
          _LiveControls(),
        ],
      ),
    );
  }
}

/// Title, connection status and the elapsed clock.
class _LiveHeader extends ConsumerWidget {
  const _LiveHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(liveControllerProvider.select((s) => s.status));
    final isRecording = ref.watch(
      liveControllerProvider.select((s) => s.isRecording),
    );
    final tagCount = ref.watch(
      liveControllerProvider.select((s) => s.trackedTagCount),
    );

    // Watching whole seconds keeps this widget at one rebuild per second
    // instead of one per frame.
    final elapsedSeconds = ref.watch(
      liveControllerProvider.select(
        (s) => (s.isRecording ? s.recordingElapsed : s.liveElapsed).inSeconds,
      ),
    );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Live', style: theme.textTheme.headlineSmall),
            const SizedBox(width: 12),
            _StatusChip(status: status, isRecording: isRecording),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$tagCount tags',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              formatElapsed(Duration(seconds: elapsedSeconds)),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isRecording ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final TrackingSourceStatus status;
  final bool isRecording;

  const _StatusChip({required this.status, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (label, color) = switch (status) {
      TrackingSourceStatus.connected =>
        isRecording
            ? ('Recording', scheme.error)
            : ('Tracking', scheme.primary),
      TrackingSourceStatus.connecting => ('Connecting', scheme.tertiary),
      TrackingSourceStatus.idle => ('Idle', scheme.outline),
      TrackingSourceStatus.disconnected => ('Offline', scheme.outline),
      TrackingSourceStatus.error => ('Error', scheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRecording && status == TrackingSourceStatus.connected
                ? Icons.fiber_manual_record
                : Icons.circle,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The court and the tags on it — the only widget that rebuilds per frame.
class _LiveCourt extends ConsumerWidget {
  const _LiveCourt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frame = ref.watch(
      liveControllerProvider.select((s) => s.latestFrame),
    );
    final court = ref.watch(setupControllerProvider.select((s) => s.court));
    final receivers = ref.watch(
      setupControllerProvider.select((s) => s.receivers),
    );
    final roster = ref.watch(liveRosterProvider);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CourtCanvas(
        court: court,
        layers: [
          const CourtSurroundLayer(),
          HandballCourtLayer(court: court),
          // Anchors are drawn behind the players: they are context here, not
          // the subject, and setup remains the place to move them.
          ReceiverLayer(receivers: receivers),
          PlayerLayer(frame: frame, roster: roster),
        ],
      ),
    );
  }
}

/// Tracking and recording buttons.
class _LiveControls extends ConsumerWidget {
  const _LiveControls();

  Future<void> _toggleRecording(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(liveControllerProvider.notifier);

    if (!ref.read(liveControllerProvider).isRecording) {
      await controller.startRecording();
      return;
    }

    final session = await controller.stopRecording();
    if (session == null || !context.mounted) return;

    final duration = session.duration ?? Duration.zero;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '${session.name} — ${session.sampleCount} samples in '
          '${formatElapsed(duration)}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(liveControllerProvider.select((s) => s.status));
    final isRecording = ref.watch(
      liveControllerProvider.select((s) => s.isRecording),
    );
    final samples = ref.watch(
      liveControllerProvider.select((s) => s.recordedSampleCount),
    );
    final error = ref.watch(
      liveControllerProvider.select((s) => s.errorMessage),
    );
    final controller = ref.read(liveControllerProvider.notifier);

    final isConnected = status == TrackingSourceStatus.connected;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // The buttons live in a Wrap inside an Expanded so that a
        // phone-width window breaks them onto two lines instead of
        // overflowing, while the status text stays at the trailing edge.
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: isConnected || isRecording
                    ? () => _toggleRecording(context, ref)
                    : null,
                style: isRecording
                    ? FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      )
                    : null,
                icon: Icon(
                  isRecording ? Icons.stop : Icons.fiber_manual_record,
                  size: 18,
                ),
                label: Text(isRecording ? 'Stop recording' : 'Start recording'),
              ),
              if (isConnected)
                OutlinedButton.icon(
                  onPressed: controller.stop,
                  icon: const Icon(Icons.pause, size: 18),
                  label: const Text('Stop tracking'),
                )
              else
                OutlinedButton.icon(
                  onPressed: controller.start,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start tracking'),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            error ??
                (isRecording || samples > 0
                    ? '$samples samples'
                    : 'Not recording'),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: error == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
