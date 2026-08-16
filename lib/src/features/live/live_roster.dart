import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/tracking_providers.dart';
import '../court/tag_roster.dart';

/// The roster the live view labels incoming frames with.
///
/// Sourced from the simulated squad for now. When real tags arrive this is
/// the one line that changes: the players, tags and assignments will come
/// from setup instead, and everything downstream already speaks the domain
/// types. Replay builds its roster from the session's own snapshot instead,
/// which is why [TagRoster] itself knows nothing about where the lists came
/// from.
final liveRosterProvider = Provider<TagRoster>((ref) {
  final squad = ref.watch(simulatedSquadProvider);
  return TagRoster.fromSetup(
    players: squad.players,
    tags: squad.tags,
    assignments: squad.assignments,
  );
});
