import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/app/provider_overrides.dart';
import 'package:kinetag/src/features/live/live_controller.dart';
import 'package:kinetag/src/features/settings/app_settings.dart';
import 'package:kinetag/src/features/settings/settings_controller.dart';
import 'package:kinetag/src/features/settings/settings_screen.dart';
import 'package:kinetag/src/features/setup/roster_panel.dart';
import 'package:kinetag/src/features/setup/setup_screen.dart';
import 'package:kinetag/src/tracking/simulator/simulation_options.dart';

late ProviderContainer container;

Future<void> pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(1200, 900),
  bool recording = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  container = ProviderContainer(
    overrides: [
      ...kinetagProviderOverrides(),
      // Stands in for an open recording. Actually starting one would leave the
      // simulator's periodic timer running, and `pumpAndSettle` never returns
      // while a repeating timer is scheduled.
      recordingInProgressProvider.overrideWith((ref) => recording),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

AppSettings get settings => container.read(appSettingsProvider);

/// The slider belonging to the setting called [label].
///
/// By label rather than by position: which slider is third on the screen is a
/// layout decision, and a test that encodes it fails every time a setting is
/// added between two others.
Finder sliderFor(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(Slider),
);

Future<void> reveal(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the current values of every setting', (tester) async {
    await pump(tester, const SettingsScreen());

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('20 Hz'), findsOneWidget);
    expect(find.text('0.5 per attack'), findsOneWidget);
    await reveal(tester, 'Implausible speed threshold');
    expect(find.text('12.0 m/s'), findsOneWidget);
    expect(find.text('200 ms'), findsOneWidget);
  });

  testWidgets('dragging a slider changes the setting it controls', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    final before = settings.analytics.maxPlausibleSpeedMps;

    // Settings are a scrolling list, and a drag aimed at a widget below the
    // fold lands on whatever is there instead.
    await reveal(tester, 'Implausible speed threshold');
    await tester.drag(
      sliderFor('Implausible speed threshold'),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();

    expect(settings.analytics.maxPlausibleSpeedMps, lessThan(before));
    expect(settings.analytics.maxPlausibleSpeedMps, greaterThanOrEqualTo(4.0));
  });

  testWidgets('reset is offered only once something has changed', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());

    final reset = find.widgetWithText(TextButton, 'Reset to defaults');
    expect(tester.widget<TextButton>(reset).onPressed, isNull);

    container.read(appSettingsProvider.notifier).setCaptureRateHz(60);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(reset).onPressed, isNotNull);

    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(settings, AppSettings.defaults);
  });

  testWidgets('the capture rate is editable when nothing is recording', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());

    expect(
      tester.widget<Slider>(sliderFor('Capture rate')).onChanged,
      isNotNull,
    );
  });

  testWidgets('the capture rate is locked while a recording is open', (
    tester,
  ) async {
    // A rate that changed mid-capture would corrupt every rate-dependent
    // metric derived from the session.
    await pump(tester, const SettingsScreen(), recording: true);

    expect(tester.widget<Slider>(sliderFor('Capture rate')).onChanged, isNull);
    expect(
      find.textContaining('Locked while recording: a rate that changed'),
      findsOneWidget,
    );
  });

  testWidgets('picking a line-up changes how many players are fielded', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());

    expect(settings.fieldPlayersOnCourt, 5);

    await tester.tap(find.text('1 + 4'));
    await tester.pumpAndSettle();
    expect(settings.fieldPlayersOnCourt, 4);

    await tester.tap(find.text('1 + 6'));
    await tester.pumpAndSettle();
    expect(settings.fieldPlayersOnCourt, 6);
  });

  testWidgets('the line-up is locked while a recording is open', (
    tester,
  ) async {
    // Substituting rebuilds the tracking source, which would end the open
    // session's stream halfway through it.
    await pump(tester, const SettingsScreen(), recording: true);

    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .onSelectionChanged,
      isNull,
    );
    expect(
      find.textContaining('Locked while recording: changing who is on court'),
      findsOneWidget,
    );
  });

  testWidgets('substitutions default to once a minute and can be turned off', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());

    expect(settings.substitutionIntervalSeconds, 60);
    expect(settings.substitutionInterval, const Duration(minutes: 1));
    expect(find.text('01:00'), findsOneWidget);

    // All the way to the left of the scale is "no substitutions", which is a
    // real way to play rather than an invalid interval.
    await tester.ensureVisible(sliderFor('Substitution interval'));
    await tester.pumpAndSettle();
    await tester.drag(
      sliderFor('Substitution interval'),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(settings.substitutesRotate, isFalse);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('the substitution interval is locked while a recording is open', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen(), recording: true);

    expect(
      tester.widget<Slider>(sliderFor('Substitution interval')).onChanged,
      isNull,
    );
  });

  testWidgets(
    'bench side, crossing rate, and substitution timing are editable',
    (tester) async {
      await pump(tester, const SettingsScreen());

      expect(settings.benchSideline, BenchSideline.bottom);
      await reveal(tester, 'Bench sideline');
      await tester.tap(find.text('Top sideline'));
      await tester.pumpAndSettle();
      expect(settings.benchSideline, BenchSideline.top);

      await reveal(tester, 'Crosses per attack');
      await tester.drag(sliderFor('Crosses per attack'), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(settings.crossesPerAttack, greaterThan(0.5));

      await reveal(tester, 'Substitution timing');
      await tester.tap(find.text('While attacking'));
      await tester.pumpAndSettle();
      expect(settings.substitutionTiming, SubstitutionTiming.whileAttacking);
    },
  );

  testWidgets('the analytics sliders stay editable while recording', (
    tester,
  ) async {
    // They only change how stored samples are interpreted, so locking them
    // would be pointless friction.
    await pump(tester, const SettingsScreen(), recording: true);

    await reveal(tester, 'Implausible speed threshold');
    expect(
      tester.widget<Slider>(sliderFor('Implausible speed threshold')).onChanged,
      isNotNull,
    );
  });

  testWidgets('the roster is editable when nothing is recording', (
    tester,
  ) async {
    await pump(tester, const SetupScreen());
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();

    expect(find.byType(RosterPanel), findsOneWidget);
    expect(find.textContaining('Recording in progress'), findsNothing);
    // The header controls are the ones always built; "Add player" sits below
    // twelve rows, outside the lazily built part of the list.
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Reset roster'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('both screens survive a phone-width window', (tester) async {
    // Overflow is an exception in a test, so this is a real assertion that the
    // roster rows and slider labels reflow rather than clipping.
    await pump(tester, const SettingsScreen(), size: const Size(420, 900));
    expect(tester.takeException(), isNull);

    await pump(tester, const SetupScreen(), size: const Size(420, 900));
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the roster is locked while a recording is open', (tester) async {
    await pump(tester, const SetupScreen(), recording: true);
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Recording in progress'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Reset roster'))
          .onPressed,
      isNull,
    );
  });
}
