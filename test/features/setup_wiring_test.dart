import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/app/provider_overrides.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/live/live_roster.dart';
import 'package:kinetag/src/features/settings/settings_controller.dart';
import 'package:kinetag/src/features/setup/roster_state.dart';
import 'package:kinetag/src/tracking/simulator/simulator_tracking_source.dart';
import 'package:kinetag/src/tracking/tracking_providers.dart';

/// A container wired exactly as the running app is.
ProviderContainer makeApp() {
  final container = ProviderContainer(overrides: kinetagProviderOverrides());
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the roster entered in setup drives the tracking source', () {
    test('the simulator emits the tags the roster declares', () {
      final container = makeApp();
      final roster = container.read(rosterControllerProvider);

      final squad = container.read(simulatedSquadProvider);

      expect(squad.participants.map((p) => p.tagId).toList(),
          roster.tags.map((t) => t.id).toList());
    });

    test('adding a player adds a simulated tag', () {
      final container = makeApp();
      container.read(rosterControllerProvider.notifier).addPlayer();

      expect(container.read(simulatedSquadProvider).length, 13);
    });

    test('shrinking a team shrinks the simulated squad', () {
      final container = makeApp();
      container
          .read(rosterControllerProvider.notifier)
          .setPlayerCount(TeamSide.away, 2);

      expect(container.read(simulatedSquadProvider).length, 8);
    });

    test('dropping to one team removes its tags from the simulation', () {
      final container = makeApp();
      container.read(rosterControllerProvider.notifier).setTeamCount(1);

      final squad = container.read(simulatedSquadProvider);
      expect(squad.length, 6);
      expect(squad.forSide(TeamSide.away), isEmpty);
    });
  });

  group('the live roster follows setup', () {
    test('labels tags with the names typed in setup', () {
      final container = makeApp();
      final target = container.read(rosterControllerProvider).members.first;

      container
          .read(rosterControllerProvider.notifier)
          .setPlayerName(target.playerId, 'Ada Hansen');

      final entry =
          container.read(liveRosterProvider).entryFor(target.tagId)!;
      expect(entry.playerName, 'Ada Hansen');
    });

    test('follows a team recolour', () {
      final container = makeApp();
      container
          .read(rosterControllerProvider.notifier)
          .setTeamColor(TeamSide.home, Team.colorPalette[5]);

      final home = container
          .read(rosterControllerProvider)
          .forSide(TeamSide.home)
          .first;
      expect(container.read(liveRosterProvider).entryFor(home.tagId)!.color,
          Color(Team.colorPalette[5]));
    });

    test('follows a team rename', () {
      final container = makeApp();
      container
          .read(rosterControllerProvider.notifier)
          .setTeamName(TeamSide.away, 'Ajax');

      final away = container
          .read(rosterControllerProvider)
          .forSide(TeamSide.away)
          .first;
      expect(container.read(liveRosterProvider).entryFor(away.tagId)!.team,
          'Ajax');
    });
  });

  group('the tracking source survives edits that do not change the capture',
      () {
    test('renaming a player does not rebuild it', () {
      // A rebuild would restart the simulated match — and, mid-recording,
      // silently break the capture. Narrow equality on `SimulatedSquad` is
      // what prevents it; this test is the guard on that.
      final container = makeApp();
      final before = container.read(trackingSourceProvider);
      final target = container.read(rosterControllerProvider).members.first;

      container
          .read(rosterControllerProvider.notifier)
          .setPlayerName(target.playerId, 'Ada Hansen');

      expect(container.read(trackingSourceProvider), same(before));
    });

    test('renaming a team does not rebuild it', () {
      final container = makeApp();
      final before = container.read(trackingSourceProvider);

      container
          .read(rosterControllerProvider.notifier)
          .setTeamName(TeamSide.home, 'Ajax');

      expect(container.read(trackingSourceProvider), same(before));
    });

    test('changing a shirt number does not rebuild it', () {
      final container = makeApp();
      final before = container.read(trackingSourceProvider);
      final target = container.read(rosterControllerProvider).members.first;

      container
          .read(rosterControllerProvider.notifier)
          .setPlayerNumber(target.playerId, 42);

      expect(container.read(trackingSourceProvider), same(before));
    });

    test('recolouring a team does not rebuild it', () {
      // Colour is presentation; the simulated movement is identical.
      final container = makeApp();
      final before = container.read(trackingSourceProvider);

      container
          .read(rosterControllerProvider.notifier)
          .setTeamColor(TeamSide.home, Team.colorPalette[6]);

      expect(container.read(trackingSourceProvider), same(before));
    });

    test('changing a role does rebuild it — the movement really changed', () {
      final container = makeApp();
      final before = container.read(trackingSourceProvider);
      final target = container.read(rosterControllerProvider).members.first;

      container
          .read(rosterControllerProvider.notifier)
          .setPlayerRole(target.playerId, PlayerRole.rightWing);

      expect(container.read(trackingSourceProvider), isNot(same(before)));
    });
  });

  group('settings reach the tracking source', () {
    test('the capture rate sets the source’s frame period', () {
      final container = makeApp();
      container.read(appSettingsProvider.notifier).setCaptureRateHz(50);

      final source =
          container.read(trackingSourceProvider) as SimulatorTrackingSource;
      expect(source.sampleRateHz, 50);
      expect(source.framePeriodMicros, 20000);
    });
  });
}
