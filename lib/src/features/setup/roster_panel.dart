import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import 'roster_state.dart';
import 'synced_text_field.dart';

/// Team and player setup: one or two sides, then who is wearing a tag.
///
/// Teams come first because everything about a player follows from theirs —
/// the colour they are drawn in, which goal they attack, how team metrics will
/// group them. Roles are optional throughout: players move between positions
/// during a match, and a squad list is useful long before anyone has decided
/// who starts where.
///
/// Editing is disabled while a recording is open. A session snapshots its
/// roster when recording starts, so an edit made mid-recording would not reach
/// the stored session anyway — but it *would* change the set of simulated
/// tags, which is a real way to corrupt a capture. Locking the panel makes
/// that impossible rather than merely unlikely.
class RosterPanel extends ConsumerWidget {
  /// Set while a recording is in progress.
  final bool locked;

  const RosterPanel({super.key, this.locked = false});

  /// Below this width each player collapses onto two rows.
  static const double _wideRowBreakpoint = 700;

  Future<void> _changeTeamCount(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final controller = ref.read(rosterControllerProvider.notifier);
    final losing = controller.playersLostByRemovingTeam(count);

    // Dropping a team discards its players — there is nowhere else for them to
    // go — so it is confirmed rather than done silently.
    if (losing > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove the second team?'),
          content: Text(
            '$losing player${losing == 1 ? '' : 's'} and their tag '
            'assignments will be removed. Recordings already saved keep the '
            'roster they were captured with.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    controller.setTeamCount(count);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roster = ref.watch(rosterControllerProvider);
    final controller = ref.read(rosterControllerProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideRowBreakpoint;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RosterHeader(
              teamCount: roster.teamCount,
              tagCount: roster.tagCount,
              locked: locked,
              onTeamCountChanged: (count) =>
                  _changeTeamCount(context, ref, count),
              onReset: controller.resetRoster,
            ),
            if (locked) ...[
              const SizedBox(height: 12),
              const _LockedNotice(
                message: 'Recording in progress — the roster is frozen so the '
                    'capture keeps the tags it started with.',
              ),
            ],
            const SizedBox(height: 16),
            for (final team in roster.teams)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _TeamCard(
                  key: ValueKey('team-${team.side.name}'),
                  team: team,
                  members: roster.forSide(team.side),
                  canMoveBetweenTeams: roster.teamCount > 1,
                  wide: wide,
                  locked: locked,
                ),
              ),
            Text(
              'Roles are optional — leave them unset for players who move '
              'between positions.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _RosterHeader extends StatelessWidget {
  final int teamCount;
  final int tagCount;
  final bool locked;
  final ValueChanged<int> onTeamCountChanged;
  final VoidCallback onReset;

  const _RosterHeader({
    required this.teamCount,
    required this.tagCount,
    required this.locked,
    required this.onTeamCountChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Nested `Wrap`s: on a phone-width window the team selector and the reset
    // button do not fit beside the title, and a `Row` would overflow rather
    // than reflow onto a second line.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                Text('Teams', style: theme.textTheme.titleMedium),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 team')),
                    ButtonSegment(value: 2, label: Text('2 teams')),
                  ],
                  selected: {teamCount},
                  showSelectedIcon: false,
                  onSelectionChanged:
                      locked ? null : (s) => onTeamCountChanged(s.first),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: locked ? null : onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset roster'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$tagCount player tag${tagCount == 1 ? '' : 's'} in total, '
          'up to ${RosterState.maxPlayersPerTeam} per team',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// One team: its name and colour, then its squad.
class _TeamCard extends ConsumerWidget {
  final Team team;
  final List<RosterMember> members;
  final bool canMoveBetweenTeams;
  final bool wide;
  final bool locked;

  const _TeamCard({
    super.key,
    required this.team,
    required this.members,
    required this.canMoveBetweenTeams,
    required this.wide,
    required this.locked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(rosterControllerProvider.notifier);
    final isFull = members.length >= RosterState.maxPlayersPerTeam;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 260,
                  child: SyncedTextField(
                    key: ValueKey('team-name-${team.side.name}'),
                    label: '${team.side.displayName} team name',
                    value: team.name,
                    enabled: !locked,
                    onCommitted: (value) =>
                        controller.setTeamName(team.side, value),
                  ),
                ),
                Text(
                  '${members.length} of ${RosterState.maxPlayersPerTeam} '
                  'players',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ColorPicker(
              side: team.side,
              selected: team.colorValue,
              enabled: !locked,
              onSelected: (value) => controller.setTeamColor(team.side, value),
            ),
            const Divider(height: 24),
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No players yet.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            for (final member in members)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlayerRow(
                  key: ValueKey(member.playerId),
                  member: member,
                  teamColorValue: team.colorValue,
                  canMoveBetweenTeams: canMoveBetweenTeams,
                  wide: wide,
                  locked: locked,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: locked || isFull
                    ? null
                    : () => controller.addPlayer(side: team.side),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: Text(isFull ? 'Squad full' : 'Add player'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The palette a team's colour is chosen from.
class _ColorPicker extends StatelessWidget {
  /// Identifies which team's picker this is, so each swatch gets a stable key.
  final TeamSide side;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelected;

  const _ColorPicker({
    required this.side,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Colour',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in Team.colorPalette)
                _ColorSwatch(
                  key: ValueKey('swatch-${side.name}-$value'),
                  value: value,
                  selected: value == selected,
                  enabled: enabled,
                  onTap: () => onSelected(value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final int value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ColorSwatch({
    super.key,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(value);

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: selected
                // Dark tick on every palette colour: they are all light
                // enough for it to read.
                ? const Icon(Icons.check, size: 16, color: Color(0xFF0C1015))
                : null,
          ),
        ),
      ),
    );
  }
}

/// One editable roster row: name, shirt number, optional role, and removal.
class _PlayerRow extends ConsumerWidget {
  final RosterMember member;
  final int teamColorValue;
  final bool canMoveBetweenTeams;
  final bool wide;
  final bool locked;

  const _PlayerRow({
    super.key,
    required this.member,
    required this.teamColorValue,
    required this.canMoveBetweenTeams,
    required this.wide,
    required this.locked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(rosterControllerProvider.notifier);
    final player = member.player;

    final marker = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: Color(teamColorValue),
        shape: BoxShape.circle,
      ),
    );

    final name = SyncedTextField(
      key: ValueKey('name-${member.playerId}'),
      label: 'Name',
      value: player.name,
      enabled: !locked,
      onCommitted: (value) {
        final trimmed = value.trim();
        // A blank name would render as an empty marker label and an empty
        // legend row, so the tag's own identity stands in instead.
        controller.setPlayerName(
          member.playerId,
          trimmed.isEmpty ? member.tag.name : trimmed,
        );
      },
    );

    final number = SizedBox(
      width: 78,
      child: SyncedTextField(
        key: ValueKey('number-${member.playerId}'),
        label: 'No.',
        value: player.number?.toString() ?? '',
        enabled: !locked,
        keyboardType: TextInputType.number,
        onCommitted: (value) => controller.setPlayerNumber(
          member.playerId,
          int.tryParse(value.trim()),
        ),
      ),
    );

    final role = SizedBox(
      width: 172,
      child: _ValueDropdown<PlayerRole?>(
        label: 'Role',
        value: player.role,
        enabled: !locked,
        values: [null, ...PlayerRole.values],
        itemBuilder: (r) => Text(
          r?.displayName ?? 'No role',
          overflow: TextOverflow.ellipsis,
          style: r == null
              ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
              : null,
        ),
        onChanged: (value) => controller.setPlayerRole(member.playerId, value),
      ),
    );

    final swap = IconButton(
      onPressed: locked
          ? null
          : () => controller.setPlayerSide(member.playerId, member.side.opposite),
      icon: const Icon(Icons.swap_horiz),
      tooltip: 'Move to the other team',
    );

    final remove = IconButton(
      onPressed:
          locked ? null : () => controller.removePlayer(member.playerId),
      icon: const Icon(Icons.close),
      tooltip: 'Remove player',
    );

    final tagLabel = Text(
      member.tag.hardwareId,
      style: theme.textTheme.labelSmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: wide
            ? Row(
                children: [
                  marker,
                  const SizedBox(width: 10),
                  Expanded(child: name),
                  const SizedBox(width: 8),
                  number,
                  const SizedBox(width: 8),
                  role,
                  const SizedBox(width: 10),
                  SizedBox(width: 64, child: tagLabel),
                  if (canMoveBetweenTeams) swap,
                  remove,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      marker,
                      const SizedBox(width: 10),
                      Expanded(child: name),
                      const SizedBox(width: 8),
                      number,
                      remove,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: role),
                      const SizedBox(width: 10),
                      tagLabel,
                      if (canMoveBetweenTeams) swap,
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// A labelled, fully controlled dropdown over a fixed set of values.
///
/// Deliberately not `DropdownButtonFormField`: that widget seeds itself from
/// an initial value and keeps its own copy, so a selection changed elsewhere
/// in the roster would not be reflected. Here the displayed value is always
/// the one passed in.
class _ValueDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final Widget Function(T) itemBuilder;
  final ValueChanged<T> onChanged;
  final bool enabled;

  const _ValueDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.itemBuilder,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        enabled: enabled,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final v in values)
              DropdownMenuItem<T>(value: v, child: itemBuilder(v)),
          ],
          onChanged: enabled ? (selected) => onChanged(selected as T) : null,
        ),
      ),
    );
  }
}

/// Explains why the controls around it are disabled.
class _LockedNotice extends StatelessWidget {
  final String message;

  const _LockedNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline,
              size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
