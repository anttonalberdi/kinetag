import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../court/tag_roster.dart';
import '../setup/roster_state.dart';

/// The roster the live view labels incoming frames with.
///
/// Sourced from the players, tags and assignments entered in setup, so a name
/// or team typed there is what appears on court and what a recording stores.
/// Replay builds its roster from the session's own snapshot instead, which is
/// why [TagRoster] itself knows nothing about where the lists came from.
final liveRosterProvider = Provider<TagRoster>((ref) {
  final roster = ref.watch(rosterControllerProvider);
  return TagRoster.fromSetup(
    players: roster.players,
    tags: roster.tags,
    assignments: roster.assignments,
    teams: roster.teams,
  );
});
