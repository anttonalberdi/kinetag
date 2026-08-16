import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/duration_format.dart';
import '../../domain/domain.dart';
import '../../storage/storage_providers.dart';
import 'analysis_navigation.dart';
import 'player_analysis_screen.dart';
import 'player_figure_screens.dart';
import 'replay_controller.dart';
import 'replay_screen.dart';
import 'session_analysis_screen.dart';

/// Recorded sessions: browse the list, open one, replay it, analyse it.
///
/// The list, the replay and the analysis pages are views of one screen rather
/// than routes, so the navigation rail stays visible on desktop and the back
/// gesture on a phone still leaves the app rather than unwinding an analysis
/// trail. [AnalysisBreadcrumbs] is what carries the reader's position
/// instead.
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  bool _replaying = false;

  Future<void> _open(Session session) async {
    // Always land on the court: opening a recording and finding yesterday's
    // analysis page would be disorienting.
    ref.read(sessionViewProvider.notifier).showReplay();
    setState(() => _replaying = true);
    await ref.read(replayControllerProvider.notifier).open(session);
  }

  Future<void> _closeSession() async {
    ref.read(sessionViewProvider.notifier).showReplay();
    setState(() => _replaying = false);
    await ref.read(replayControllerProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    if (!_replaying) return _SessionList(onOpen: _open);

    return switch (ref.watch(sessionViewProvider)) {
      ReplayView() => ReplayScreen(onBack: _closeSession),
      TeamAnalysisView() =>
        SessionAnalysisScreen(onBackToSessions: _closeSession),
      PlayerAnalysisView(:final tagId) => PlayerAnalysisScreen(
          tagId: tagId,
          onBackToSessions: _closeSession,
        ),
      PlayerHeatmapView(:final tagId) => PlayerHeatmapScreen(
          tagId: tagId,
          onBackToSessions: _closeSession,
        ),
      PlayerSpeedView(:final tagId) => PlayerSpeedScreen(
          tagId: tagId,
          onBackToSessions: _closeSession,
        ),
    };
  }
}

class _SessionList extends ConsumerWidget {
  final void Function(Session session) onOpen;

  const _SessionList({required this.onOpen});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(
          '“${session.name}” and its ${session.sampleCount} samples will be '
          'removed permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(sessionRepositoryProvider).deleteSession(session.id);
    ref.invalidate(sessionListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionListProvider);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Sessions', style: theme.textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                onPressed: () => ref.invalidate(sessionListProvider),
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: sessions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Could not read recordings: $error',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
              data: (sessions) => sessions.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return _SessionTile(
                          session: session,
                          onOpen: () => onOpen(session),
                          onDelete: () =>
                              _confirmDelete(context, ref, session),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final Session session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = session.duration;
    final playable = session.sampleCount > 0;

    return ListTile(
      onTap: playable ? onOpen : null,
      enabled: playable,
      leading: Icon(
        playable ? Icons.play_circle_outline : Icons.error_outline,
        color: playable ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(session.name),
      subtitle: Text(
        [
          session.status.displayName,
          if (duration != null) formatElapsed(duration),
          '${session.sampleCount} samples',
          '${session.players.length} players',
        ].join(' • '),
      ),
      trailing: IconButton(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete recording',
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('No recordings yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Record one from the Live tab and it will appear here.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
