import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/setup/roster_panel.dart';
import 'package:kinetag/src/features/setup/roster_state.dart';

late ProviderContainer container;

Future<void> pumpRoster(
  WidgetTester tester, {
  Size size = const Size(1100, 900),
  bool locked = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: RosterPanel(locked: locked))),
    ),
  );
  await tester.pumpAndSettle();
}

RosterState get roster => container.read(rosterControllerProvider);
RosterController get controller =>
    container.read(rosterControllerProvider.notifier);

Finder scrollable() => find
    .descendant(of: find.byType(RosterPanel), matching: find.byType(Scrollable))
    .first;

void main() {
  testWidgets('shows a card per team', (tester) async {
    await pumpRoster(tester);

    expect(find.text('Home team name'), findsOneWidget);
    expect(find.textContaining('6 of 15 players'), findsWidgets);
    expect(find.text('2 teams'), findsOneWidget);
  });

  testWidgets('renaming a team relabels its players', (tester) async {
    await pumpRoster(tester);

    final field = find.widgetWithText(TextField, 'Home');
    await tester.enterText(field, 'Ajax');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(roster.teamName(TeamSide.home), 'Ajax');
    expect(roster.forSide(TeamSide.home).every((m) => m.player.team == 'Ajax'),
        isTrue);
  });

  testWidgets('picking a colour changes the team it belongs to',
      (tester) async {
    await pumpRoster(tester);
    final before = roster.teamColorValue(TeamSide.home);

    await tester
        .tap(find.byKey(ValueKey('swatch-home-${Team.colorPalette[4]}')));
    await tester.pumpAndSettle();

    expect(roster.teamColorValue(TeamSide.home), isNot(before));
    expect(roster.teamColorValue(TeamSide.home), Team.colorPalette[4]);
  });

  testWidgets('a role can be cleared from the dropdown', (tester) async {
    await pumpRoster(tester);
    final target = roster.members.first;
    expect(target.role, isNotNull);

    await tester.tap(find.byType(DropdownButton<PlayerRole?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('No role').last);
    await tester.pumpAndSettle();

    expect(
      roster.members.firstWhere((m) => m.playerId == target.playerId).role,
      isNull,
    );
  });

  testWidgets('dropping to one team asks before discarding its players',
      (tester) async {
    await pumpRoster(tester);

    await tester.tap(find.text('1 team'));
    await tester.pumpAndSettle();

    expect(find.text('Remove the second team?'), findsOneWidget);
    expect(find.textContaining('6 players'), findsOneWidget);

    // Cancelling leaves the roster exactly as it was.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(roster.teamCount, 2);
    expect(roster.tagCount, 12);
  });

  testWidgets('confirming the dialog removes the team and its players',
      (tester) async {
    await pumpRoster(tester);

    await tester.tap(find.text('1 team'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(roster.teamCount, 1);
    expect(roster.tagCount, 6);
    expect(find.text('Away team name'), findsNothing);
  });

  testWidgets('an empty second team is added back without a prompt',
      (tester) async {
    await pumpRoster(tester);
    controller.setPlayerCount(TeamSide.away, 0);
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 team'));
    await tester.pumpAndSettle();

    // Nothing would be lost, so no confirmation is shown.
    expect(find.text('Remove the second team?'), findsNothing);
    expect(roster.teamCount, 1);
  });

  testWidgets('a full squad disables its add button', (tester) async {
    await pumpRoster(tester);
    controller.setPlayerCount(TeamSide.home, RosterState.maxPlayersPerTeam);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Squad full').first, 300,
        scrollable: scrollable());
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Squad full').first)
          .onPressed,
      isNull,
    );
  });

  testWidgets('survives a phone-width window', (tester) async {
    await pumpRoster(tester, size: const Size(420, 900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('locking disables the team controls', (tester) async {
    await pumpRoster(tester, locked: true);

    expect(find.textContaining('Recording in progress'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .onSelectionChanged,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Home')).enabled,
      isFalse,
    );
  });
}
