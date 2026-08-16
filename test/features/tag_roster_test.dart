import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/court/handball_court_layer.dart';
import 'package:kinetag/src/features/court/tag_roster.dart';
import 'package:kinetag/src/features/court/player_layer.dart';
import 'package:kinetag/src/features/setup/roster_state.dart';
import 'package:kinetag/src/tracking/simulator/match_simulation.dart';
import 'package:kinetag/src/tracking/simulator/simulated_squad.dart';

TagRoster rosterFor(RosterState setup) => TagRoster.fromSetup(
      players: setup.players,
      tags: setup.tags,
      assignments: setup.assignments,
      teams: setup.teams,
    );

void main() {
  // The on-court appearance is built from the roster entered in setup, and
  // the simulator emits positions for the tags that roster declares.
  final setup = RosterState.defaults();
  final roster = rosterFor(setup);
  final squad = SimulatedSquad.fromRoster(
    players: setup.players,
    tags: setup.tags,
    assignments: setup.assignments,
  );

  group('roster', () {
    test('gives each team its own colour', () {
      final home =
          roster.entryFor(squad.forSide(TeamSide.home).first.tagId)!;
      final away =
          roster.entryFor(squad.forSide(TeamSide.away).first.tagId)!;

      expect(home.color, isNot(away.color));
      expect(home.color, TagRoster.teamColors[0]);
      expect(away.color, TagRoster.teamColors[1]);
    });

    test('labels players with their shirt number', () {
      final entry = roster.entryFor(
        squad.participants.firstWhere((p) => p.role == PlayerRole.pivot).tagId,
      )!;

      expect(entry.label, '${PlayerRole.pivot.defaultShirtNumber}');
      expect(entry.labelPainter.width, greaterThan(0),
          reason: 'labels are laid out once, off the render path');
    });

    test('falls back gracefully for a tag with no player', () {
      final orphan = TagRoster.fromSetup(
        players: const [],
        assignments: const [],
        tags: const [Tag(id: 't-9', hardwareId: 'HW-4711', name: 'Spare')],
      );

      final entry = orphan.entryFor('t-9')!;
      expect(entry.color, TagRoster.unassignedColor);
      expect(entry.label, '711');
    });

    test('returns null for a tag nobody registered', () {
      expect(roster.entryFor('unknown-tag'), isNull);
    });
  });

  group('team colours', () {
    test('follow the colour chosen for the team', () {
      final recoloured = setup.copyWith(
        teams: [
          setup.teams.first.copyWith(colorValue: Team.colorPalette[5]),
          ...setup.teams.skip(1),
        ],
      );
      final built = rosterFor(recoloured);
      final home = recoloured.forSide(TeamSide.home).first;

      expect(built.entryFor(home.tagId)!.color,
          const Color(0xFFFF6B6B));
      expect(built.entryFor(home.tagId)!.color,
          Color(Team.colorPalette[5]));
    });

    test('follow a team rename', () {
      final renamed = setup.copyWith(
        teams: [
          setup.teams.first.copyWith(name: 'Ajax'),
          ...setup.teams.skip(1),
        ],
      );
      final home = renamed.forSide(TeamSide.home).first;

      expect(rosterFor(renamed).entryFor(home.tagId)!.team, 'Ajax');
    });

    test('fall back to appearance order for a session with no teams', () {
      // Sessions recorded before teams were user-defined carry none. They must
      // still replay in two distinguishable colours.
      final legacy = TagRoster.fromSetup(
        players: setup.players,
        tags: setup.tags,
        assignments: setup.assignments,
      );

      final home = setup.forSide(TeamSide.home).first;
      final away = setup.forSide(TeamSide.away).first;
      expect(legacy.entryFor(home.tagId)!.color, TagRoster.teamColors[0]);
      expect(legacy.entryFor(away.tagId)!.color, TagRoster.teamColors[1]);
      expect(legacy.entryFor(home.tagId)!.color,
          isNot(legacy.entryFor(away.tagId)!.color));
    });
  });

  group('repaint policy', () {
    final frameA = PositionFrame(timestampMicros: 1, samples: const []);
    final frameB = PositionFrame(timestampMicros: 2, samples: const []);

    test('repaints when the frame instant changes', () {
      expect(
        PlayerLayer(frame: frameB, roster: roster)
            .shouldRepaint(PlayerLayer(frame: frameA, roster: roster)),
        isTrue,
      );
    });

    test('does not repaint for the same frame', () {
      expect(
        PlayerLayer(frame: frameA, roster: roster)
            .shouldRepaint(PlayerLayer(frame: frameA, roster: roster)),
        isFalse,
      );
    });

    test('repaints when the roster is replaced', () {
      expect(
        PlayerLayer(frame: frameA, roster: rosterFor(setup))
            .shouldRepaint(PlayerLayer(frame: frameA, roster: roster)),
        isTrue,
      );
    });
  });

  testWidgets('players rasterise onto the court in team colours',
      (tester) async {
    // Renders through the real compositor, the same path the macOS app uses,
    // and writes build/live_render.png for inspection by eye — screen capture
    // is not available in this environment.
    final key = GlobalKey();
    final court = Court.handball();
    final frame = MatchSimulation(court: court, squad: squad, seed: 4)
        .advance(dtMicros: 50000, timestampMicros: 50000);

    tester.view.physicalSize = const ui.Size(1400, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: CourtCanvas(
              court: court,
              layers: [
                const CourtSurroundLayer(),
                HandballCourtLayer(court: court),
                PlayerLayer(frame: frame, roster: roster),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);

      final outDir = Directory('build');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      File('build/live_render.png').writeAsBytesSync(png!.buffer.asUint8List());

      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var homePixels = 0;
      var awayPixels = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        final color = Color.fromARGB(
          255,
          pixels.getUint8(i),
          pixels.getUint8(i + 1),
          pixels.getUint8(i + 2),
        );
        if (color == TagRoster.teamColors[0]) homePixels++;
        if (color == TagRoster.teamColors[1]) awayPixels++;
      }

      // Six markers a side, ~11 px radius: hundreds of pixels each even
      // allowing for the outline and the label punched through the middle.
      expect(homePixels, greaterThan(500));
      expect(awayPixels, greaterThan(500));
    });
  });
}
