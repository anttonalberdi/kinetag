
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/core/court_view_transform.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/setup/coordinate_field.dart';
import 'package:kinetag/src/features/setup/roster_panel.dart';
import 'package:kinetag/src/features/setup/roster_state.dart';
import 'package:kinetag/src/features/setup/setup_screen.dart';
import 'package:kinetag/src/features/setup/setup_state.dart';

late ProviderContainer container;

Future<void> pumpSetup(WidgetTester tester,
    {Size size = const Size(1400, 850)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SetupScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

SetupState get state => container.read(setupControllerProvider);

/// Global screen position of a world point inside the court canvas.
Offset globalPositionOf(WidgetTester tester, Offset world) {
  final canvasRect = tester.getRect(find.byType(CourtCanvas));
  final canvas = tester.widget<CourtCanvas>(find.byType(CourtCanvas));

  final transform = CourtViewTransform.fit(
    visibleWorld: canvas.visibleWorldFor(canvas.court),
    viewport: canvasRect.size,
    padding: canvas.paddingPixels,
  );
  return canvasRect.topLeft + transform.worldToScreen(world);
}

Offset worldOf(dynamic r) => Offset(r.x as double, r.y as double);

void main() {
  testWidgets('shows the court and six receivers', (tester) async {
    await pumpSetup(tester);

    expect(find.byType(CourtCanvas), findsOneWidget);
    expect(state.receivers, hasLength(6));
    expect(find.textContaining('Ring layout'), findsOneWidget);
  });

  testWidgets('the count selector switches to another layout preset',
      (tester) async {
    await pumpSetup(tester);

    // The segments are labelled with the count itself.
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('3'),
      ),
    );
    await tester.pumpAndSettle();

    expect(state.receivers, hasLength(3));
    expect(state.layoutShape, ReceiverLayoutShape.triangle);
    expect(find.textContaining('Triangle layout'), findsOneWidget);
  });

  testWidgets('switching to the players section shows the roster',
      (tester) async {
    await pumpSetup(tester);

    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();

    expect(find.byType(RosterPanel), findsOneWidget);
    expect(find.byType(CourtCanvas), findsNothing);
    expect(find.textContaining('12 player tags in total'), findsOneWidget);
    expect(find.text('2 teams'), findsOneWidget);
    // The home team's card is the one on screen; the away card sits below the
    // fold of the lazily built list.
    expect(find.text('Home team name'), findsOneWidget);
    expect(container.read(rosterControllerProvider).teamCount, 2);
  });

  testWidgets('adding a player from a team card grows that squad',
      (tester) async {
    await pumpSetup(tester);
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();

    // The home team's button sits below its six player rows, outside the
    // built part of the lazy list.
    await tester.scrollUntilVisible(
      find.text('Add player').first,
      300,
      scrollable: find
          .descendant(
            of: find.byType(RosterPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add player').first);
    await tester.pumpAndSettle();

    final roster = container.read(rosterControllerProvider);
    expect(roster.playerCount(TeamSide.home), 7);
    expect(roster.playerCount(TeamSide.away), 6);
  });

  testWidgets('starts with nothing selected', (tester) async {
    await pumpSetup(tester);

    expect(state.selectedReceiver, isNull);
    expect(find.text('No receiver selected'), findsOneWidget);
  });

  testWidgets('clicking a receiver selects it and opens the inspector',
      (tester) async {
    await pumpSetup(tester);
    final target = state.receivers.first;

    await tester.tapAt(globalPositionOf(tester, worldOf(target)));
    await tester.pumpAndSettle();

    expect(state.selectedReceiverId, target.id);
    expect(find.text(target.name), findsOneWidget);
    // Inspector now shows X / Y / Height fields.
    expect(find.byType(CoordinateField), findsNWidgets(3));
  });

  testWidgets('inspector lists distances to the other five receivers',
      (tester) async {
    await pumpSetup(tester);
    await tester
        .tapAt(globalPositionOf(tester, worldOf(state.receivers.first)));
    await tester.pumpAndSettle();

    expect(find.text('Distances'), findsOneWidget);
    for (final other in state.receivers.skip(1)) {
      expect(find.text(other.name), findsOneWidget);
    }
  });

  testWidgets('clicking empty court clears the selection', (tester) async {
    await pumpSetup(tester);
    await tester
        .tapAt(globalPositionOf(tester, worldOf(state.receivers.first)));
    await tester.pumpAndSettle();
    expect(state.selectedReceiver, isNotNull);

    // Centre of the court, far from every perimeter receiver.
    await tester.tapAt(globalPositionOf(tester, const Offset(20, 10)));
    await tester.pumpAndSettle();

    expect(state.selectedReceiver, isNull);
  });

  testWidgets('dragging a receiver updates its real-world coordinates',
      (tester) async {
    await pumpSetup(tester);
    final target = state.receivers.first;
    final startX = target.x;
    final startY = target.y;

    await tester.dragFrom(
      globalPositionOf(tester, worldOf(target)),
      const Offset(60, 40), // pixels
    );
    await tester.pumpAndSettle();

    final moved =
        state.receivers.firstWhere((r) => r.id == target.id);
    expect(moved.x, greaterThan(startX));
    expect(moved.y, greaterThan(startY));
    // Height is untouched by a planar drag.
    expect(moved.z, target.z);
  });

  testWidgets('a drag of N pixels moves the receiver the equivalent metres',
      (tester) async {
    // Guards the transform wiring: pixels must convert through the same
    // scale used to draw, or dragging would drift.
    await pumpSetup(tester);
    final target = state.receivers.first;

    final canvasRect = tester.getRect(find.byType(CourtCanvas));
    final canvas = tester.widget<CourtCanvas>(find.byType(CourtCanvas));
    final transform = CourtViewTransform.fit(
      visibleWorld: canvas.visibleWorldFor(canvas.court),
      viewport: canvasRect.size,
      padding: canvas.paddingPixels,
    );

    const dragPixels = Offset(80, 0);
    await tester.dragFrom(
        globalPositionOf(tester, worldOf(target)), dragPixels);
    await tester.pumpAndSettle();

    final moved = state.receivers.firstWhere((r) => r.id == target.id);
    expect(
      moved.x - target.x,
      closeTo(transform.pixelsToMetres(dragPixels.dx), 0.01),
    );
  });

  testWidgets('typing a coordinate repositions the receiver precisely',
      (tester) async {
    await pumpSetup(tester);
    final target = state.receivers.first;
    await tester.tapAt(globalPositionOf(tester, worldOf(target)));
    await tester.pumpAndSettle();

    final xField = find.byType(TextField).first;
    await tester.tap(xField);
    await tester.pumpAndSettle();
    await tester.enterText(xField, '-3.75');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      state.receivers.firstWhere((r) => r.id == target.id).x,
      closeTo(-3.75, 1e-9),
    );
  });

  testWidgets('reset restores the default layout', (tester) async {
    await pumpSetup(tester);
    final target = state.receivers.first;
    container
        .read(setupControllerProvider.notifier)
        .moveReceiver(target.id, x: 99);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset layout'));
    await tester.pumpAndSettle();

    expect(state.receivers, defaultReceiverLayout(state.court));
  });

  testWidgets('narrow window stacks the inspector below the court',
      (tester) async {
    // The layout must survive a phone-sized window without overflowing.
    await pumpSetup(tester, size: const Size(600, 900));

    expect(find.byType(CourtCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
