import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/analytics/occupancy_grid.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/court/court_canvas.dart';
import 'package:kinetag/src/features/sessions/heatmap_panel.dart';

const int kStartMicros = 1786000000000000;

final Court kCourt = Court.handball();

/// A tag standing at `(x, y)` for a second, sampled at 10 Hz.
OccupancyGrid gridAt(double x, double y) => OccupancyGrid.fromTrack(
      [
        for (var i = 0; i < 11; i++)
          PositionSample(
            timestampMicros: kStartMicros + i * 100000,
            tagId: 'tag-1',
            x: x,
            y: y,
          ),
      ],
      court: kCourt,
    );

/// The preview on its own, with no session behind it.
Future<void> pumpPreview(
  WidgetTester tester,
  List<HeatmapSelection> selections, {
  String title = 'Player 0 • where the time was spent',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: HeatmapPreview(
              court: kCourt,
              selections: selections,
              title: title,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a map with nothing on it says so rather than drawing an '
      'empty court', (tester) async {
    await pumpPreview(tester, [
      HeatmapSelection(
        label: 'Player 0',
        color: Colors.blue,
        grid: OccupancyGrid.empty(court: kCourt),
      ),
    ]);

    expect(find.text('No positions on court were mapped.'), findsOneWidget);
    expect(find.byType(CourtCanvas), findsNothing);
  });

  testWidgets('the thumbnail opens the full map, and closes back to the page',
      (tester) async {
    await pumpPreview(tester, [
      HeatmapSelection(
        label: 'Player 0',
        color: Colors.blue,
        grid: gridAt(10.25, 5.25),
        side: TeamSide.home,
      ),
    ]);

    expect(find.byType(CourtCanvas), findsOneWidget, reason: 'the thumbnail');
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.byType(CourtHeatmap));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Player 0 • where the time was spent'), findsOneWidget);
    // A single map has nothing to be compared against, so no chips.
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(CourtCanvas), findsOneWidget);
  });

  testWidgets('the figures beside the map are read off the unsmoothed grid',
      (tester) async {
    await pumpPreview(tester, [
      HeatmapSelection(
        label: 'Player 0',
        color: Colors.blue,
        grid: gridAt(10.25, 5.25),
        side: TeamSide.home,
      ),
    ]);

    await tester.tap(find.byType(CourtHeatmap));
    await tester.pumpAndSettle();

    // One second, all of it in one square in the half this side defends.
    expect(find.text('TIME MAPPED'), findsOneWidget);
    expect(find.text('00:01'), findsNWidgets(2), reason: 'total and peak');
    expect(find.text('OWN HALF'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget, reason: '1 of 3200 squares');
  });

  testWidgets('a side that defends the other goal counts the other half',
      (tester) async {
    await pumpPreview(tester, [
      HeatmapSelection(
        label: 'Player 0',
        color: Colors.blue,
        grid: gridAt(10.25, 5.25),
        side: TeamSide.away,
      ),
    ]);

    await tester.tap(find.byType(CourtHeatmap));
    await tester.pumpAndSettle();

    expect(find.text('0%'), findsNWidgets(2), reason: 'own half and coverage');
    expect(find.textContaining('Defending the right goal'), findsOneWidget);
  });

  testWidgets('without a recorded side there is no own-half figure to give',
      (tester) async {
    await pumpPreview(tester, [
      HeatmapSelection(
        label: 'Player 0',
        color: Colors.blue,
        grid: gridAt(10.25, 5.25),
      ),
    ]);

    await tester.tap(find.byType(CourtHeatmap));
    await tester.pumpAndSettle();

    expect(find.text('TIME MAPPED'), findsOneWidget);
    expect(find.text('OWN HALF'), findsNothing);
  });

  testWidgets('the chips switch which map is drawn', (tester) async {
    await pumpPreview(
      tester,
      [
        HeatmapSelection(
          label: 'Ajax',
          color: Colors.blue,
          grid: gridAt(10.25, 5.25),
        ),
        HeatmapSelection(
          label: 'Player 0',
          color: Colors.orange,
          // Two seconds, so the figures differ from the team's one.
          grid: OccupancyGrid.merged([
            gridAt(30.25, 15.25),
            gridAt(30.25, 15.25),
          ]),
        ),
      ],
      title: 'Ajax • where the time was spent',
    );

    await tester.tap(find.byType(CourtHeatmap));
    await tester.pumpAndSettle();

    expect(find.text('00:01'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Player 0'));
    await tester.pumpAndSettle();

    expect(find.text('00:02'), findsNWidgets(2));
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Player 0'))
          .selected,
      isTrue,
    );
    // The title still names what was opened, not what is being looked at.
    expect(find.text('Ajax • where the time was spent'), findsOneWidget);
  });
}
