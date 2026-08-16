import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/core/court_view_transform.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/sessions/analysis_widgets.dart';
import 'package:kinetag/src/features/sessions/heatmap_panel.dart';
import 'package:kinetag/src/features/sessions/player_analysis_screen.dart';
import 'package:kinetag/src/features/sessions/player_figure_screens.dart';
import 'package:kinetag/src/features/sessions/replay_controller.dart';
import 'package:kinetag/src/features/sessions/replay_screen.dart';
import 'package:kinetag/src/features/sessions/session_analysis_screen.dart';
import 'package:kinetag/src/features/sessions/sessions_screen.dart';
import 'package:kinetag/src/storage/storage_providers.dart';

import '../support/fake_session_repository.dart';
import '../support/session_fixtures.dart';

late ProviderContainer container;
late FakeSessionRepository repository;

ReplayState get replayState => container.read(replayControllerProvider);

/// Opens the seeded recording and leaves the replay screen on screen.
Future<void> pumpReplay(
  WidgetTester tester, {
  String name = 'Tuesday',
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SessionsScreen())),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// Where a world point sits on screen, for tapping a player marker.
Offset screenPointFor(WidgetTester tester, Offset world) {
  final canvas = tester.getRect(find.byType(CourtCanvas));
  final transform = CourtViewTransform.fit(
    visibleWorld: const Rect.fromLTRB(-5, -5, 45, 25),
    viewport: canvas.size,
    padding: 12,
  );
  return canvas.topLeft + transform.worldToScreen(world);
}

/// Scrolls the team page down to its ranking table.
///
/// The table sits below the team cards, and their maps put it under the fold
/// of anything short of a very tall window.
Future<void> scrollToPlayerTable(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byType(DataTable), 200);
  await tester.pumpAndSettle();
}

/// Opens a player's page through the team page's ranking table.
///
/// The route a phone-width window has: the movement panel that opens a player
/// straight from the court has no room beside it at that width.
Future<void> openPlayerFromTable(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Analysis'));
  await tester.pumpAndSettle();

  final row =
      find.descendant(of: find.byType(DataTable), matching: find.text(name));
  // The table is below the fold on a phone: scroll it into the list, then the
  // rest of the way onto the screen.
  await tester.scrollUntilVisible(row, 200);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// A player's own page shows their name twice: as the last breadcrumb and as
/// the heading.
void expectPlayerPage(String name) {
  expect(find.byType(PlayerAnalysisScreen), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(PlayerAnalysisScreen),
      matching: find.text(name),
    ),
    findsNWidgets(2),
    reason: 'breadcrumb and heading',
  );
}

void main() {
  setUp(() {
    repository = FakeSessionRepository();
    container = ProviderContainer(
      overrides: [sessionRepositoryProvider.overrideWith((ref) => repository)],
    );
  });

  tearDown(() => container.dispose());

  group('player page', () {
    testWidgets('opens from the movement panel, as a page with breadcrumbs',
        (tester) async {
      // Each seeded tag moves 1 m every 100 ms: 9 m at a steady 10 m/s.
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);

      await tester.tap(find.text('Player 0'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerAnalysisScreen), findsOneWidget);
      // The replay is gone: this is a page, not a layer over it. The one
      // court on it is the player's own heatmap, which carries no transport.
      expect(find.byType(ReplayScreen), findsNothing);
      expect(find.byType(CourtHeatmap), findsOneWidget);
      expect(find.byType(CourtCanvas), findsOneWidget);

      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('9.0 m'), findsOneWidget);
      expect(find.textContaining('of 2 by distance'), findsOneWidget);
      expect(find.text('Speed over time'), findsOneWidget);

      // The intensity split sits below the time sections the page gained, so
      // it is reached by scrolling rather than on arrival.
      await tester.scrollUntilVisible(find.text('Time by intensity'), 200);
      expect(find.text('Time by intensity'), findsOneWidget);
      expect(find.textContaining('Sprinting 100%'), findsOneWidget);

      // Breadcrumbs name the trail out: session list, court, team analysis.
      expect(find.widgetWithText(TextButton, 'Sessions'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Tuesday'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Analysis'), findsOneWidget);
    });

    testWidgets('opens from a marker on the court', (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);

      // tag-1 starts at (1, 6); the empty floor beside it must not navigate.
      await tester.tapAt(screenPointFor(tester, const Offset(20, 15)));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerAnalysisScreen), findsNothing);

      await tester.tapAt(screenPointFor(tester, const Offset(1, 6)));
      await tester.pumpAndSettle();

      expectPlayerPage('Player 1');
    });

    testWidgets('breadcrumbs lead back to the court and to the session list',
        (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);
      await tester.tap(find.text('Player 0'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Tuesday'));
      await tester.pumpAndSettle();
      expect(find.byType(CourtCanvas), findsOneWidget);
      expect(replayState.session, isNotNull);

      await tester.tap(find.text('Player 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sessions'));
      await tester.pumpAndSettle();

      expect(find.text('Sessions'), findsWidgets, reason: 'the list heading');
      expect(replayState.session, isNull);
    });

    testWidgets('steps between players without leaving the page',
        (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);
      await tester.tap(find.text('Player 0'));
      await tester.pumpAndSettle();

      final forward = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down),
      );
      await tester.tap(
        forward.onPressed == null
            ? find.byTooltip('Previous player')
            : find.byTooltip('Next player'),
      );
      await tester.pumpAndSettle();

      expectPlayerPage('Player 1');
    });

    testWidgets('shows the map and the speed chart side by side when wide',
        (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);
      await tester.tap(find.text('Player 0'));
      await tester.pumpAndSettle();

      final map = tester.getRect(find.byType(PlayerHeatmapCard));
      final chart = tester.getRect(find.byType(SpeedChart));

      expect(map.right, lessThanOrEqualTo(chart.left), reason: 'one row');
      expect(map.top, chart.top);
      expect(map.height, chart.height);
    });

    testWidgets('stacks the map above the speed chart when narrow',
        (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      // Reached through the team page: the movement panel that opens a player
      // directly has no room beside the court at this width.
      await pumpReplay(tester, size: const Size(420, 780));
      await openPlayerFromTable(tester, 'Player 0');

      // Both figures are below the fold at this width; scrolling to the lower
      // one leaves the pair built and measurable.
      await tester.scrollUntilVisible(find.byType(SpeedChart), 200);
      await tester.pumpAndSettle();

      final map = tester.getRect(find.byType(PlayerHeatmapCard));
      final chart = tester.getRect(find.byType(SpeedChart));

      expect(map.bottom, lessThanOrEqualTo(chart.top), reason: 'stacked');
      expect(map.left, chart.left);
      expect(map.width, chart.width);
    });

    testWidgets('the speed chart opens its own page, where it scrubs',
        (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);
      await tester.tap(find.text('Player 0'));
      await tester.pumpAndSettle();

      // On the player page the chart is a preview: a tap there navigates
      // rather than seeking.
      expect(replayState.position, Duration.zero);
      await tester.tap(find.byType(SpeedChart));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerSpeedScreen), findsOneWidget);
      expect(replayState.position, Duration.zero);
      // The explanation the player page leaves out lives here.
      expect(find.textContaining('measured over a'), findsOneWidget);
      expect(find.text('Time by intensity'), findsOneWidget);

      final chart = tester.getRect(find.byType(SpeedChart));
      await tester.tapAt(Offset(chart.right - 12, chart.center.dy));
      await tester.pumpAndSettle();

      expect(replayState.position, greaterThan(Duration.zero));

      // And the trail leads back through the player, not out of the session.
      await tester.tap(find.widgetWithText(TextButton, 'Player 0'));
      await tester.pumpAndSettle();
      expectPlayerPage('Player 0');
    });

    testWidgets('the movement map opens its own page from the preview',
        (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);
      await tester.tap(find.text('Player 0'));
      await tester.pumpAndSettle();

      expect(find.text('Where the time was spent'), findsOneWidget);

      await tester.tap(find.byType(CourtHeatmap));
      await tester.pumpAndSettle();

      // The full-size map arrives with the figures the thumbnail has no room
      // for, and with the note explaining what a square holds.
      expect(find.byType(PlayerHeatmapScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('TIME MAPPED'), findsOneWidget);
      expect(find.text('BUSIEST SQUARE'), findsOneWidget);
      expect(find.text('FLOOR COVERED'), findsOneWidget);
      expect(find.byType(HeatmapScaleLegend), findsOneWidget);
      expect(find.textContaining('Each square is'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Player 0'));
      await tester.pumpAndSettle();

      expectPlayerPage('Player 0');
    });

    testWidgets('lays out in a phone-width window', (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester, size: const Size(420, 780));
      await openPlayerFromTable(tester, 'Player 0');

      expectPlayerPage('Player 0');
      // The page scrolls on a phone rather than compressing: the sections
      // below the fold are reachable, and laying them out at this width
      // raises no overflow.
      await tester.scrollUntilVisible(find.text('Time by intensity'), 200);
      expect(find.text('Time by intensity'), findsOneWidget);
    });
  });

  group('team analysis page', () {
    testWidgets('reports session totals and splits them by team',
        (tester) async {
      // Two players, one per team, each covering 9 m.
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Analysis'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionAnalysisScreen), findsOneWidget);
      // Game time comes first, then the totals — which are scoped to playing
      // time by default, and say so.
      expect(find.text('Game time'), findsOneWidget);
      expect(find.text('Totals — on court'), findsOneWidget);
      expect(find.text('18.0 m'), findsOneWidget, reason: 'squad total');
      expect(find.text('2'), findsWidgets, reason: 'players tracked');

      // Both sides appear as their own card, each with its own total.
      expect(find.text('By team'), findsOneWidget);
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Away'), findsWidgets);
      // Each side's card carries that side's own total, not the squad's.
      final homeCard =
          find.ancestor(of: find.text('Home'), matching: find.byType(Card));
      expect(
        find.descendant(of: homeCard, matching: find.text('9.0 m')),
        findsOneWidget,
      );

      // And the ranking lists every player.
      await scrollToPlayerTable(tester);
      expect(find.text('Players'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('Player 0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a player row opens that player’s page', (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Analysis'));
      await tester.pumpAndSettle();
      await scrollToPlayerTable(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('Player 1'),
        ),
      );
      await tester.pumpAndSettle();

      expectPlayerPage('Player 1');
    });

    testWidgets('every team card carries a map of that side', (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Analysis'));
      await tester.pumpAndSettle();

      expect(find.byType(TeamHeatmapCard), findsNWidgets(2));

      final homeCard =
          find.ancestor(of: find.text('Home'), matching: find.byType(Card));
      final homeMap =
          find.descendant(of: homeCard, matching: find.byType(CourtHeatmap));
      await tester.scrollUntilVisible(homeMap, 200);
      await tester.pumpAndSettle();

      await tester.tap(homeMap);
      await tester.pumpAndSettle();

      // The team's own map opens first, with the players behind it offered
      // as the thing to read it against.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining('Home •'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Home'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Player 0'), findsOneWidget);
      // Only this side's players: Player 1 is on the other card's map.
      expect(find.widgetWithText(ChoiceChip, 'Player 1'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Player 0'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Player 0'))
            .selected,
        isTrue,
      );
    });

    testWidgets('returns to the court from the breadcrumb', (tester) async {
      await seedRecording(repository, name: 'Tuesday');
      await pumpReplay(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Analysis'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Tuesday'));
      await tester.pumpAndSettle();

      expect(find.byType(CourtCanvas), findsOneWidget);
    });
  });
}
