import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';
import 'package:kinetag/src/features/settings/settings_controller.dart';
import 'package:kinetag/src/features/setup/setup_state.dart';

ProviderContainer makeContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

SetupState readState(ProviderContainer c) => c.read(setupControllerProvider);
SetupController controllerOf(ProviderContainer c) =>
    c.read(setupControllerProvider.notifier);

/// True when every receiver sits off the floor of play.
bool allOutsideCourt(SetupState state) {
  final court =
      Rect.fromLTWH(0, 0, state.court.widthMeters, state.court.heightMeters);
  return state.receivers.every((r) => !court.contains(Offset(r.x, r.y)));
}

void main() {
  final court = Court.handball();

  group('layout presets', () {
    test('map each supported count to its shape', () {
      expect(ReceiverLayoutShape.forCount(3), ReceiverLayoutShape.triangle);
      expect(ReceiverLayoutShape.forCount(4), ReceiverLayoutShape.square);
      expect(
          ReceiverLayoutShape.forCount(5), ReceiverLayoutShape.squarePlusApex);
      expect(ReceiverLayoutShape.forCount(6), ReceiverLayoutShape.ring);
    });

    test('produce exactly the requested number of receivers', () {
      for (var n = minReceiverCount; n <= maxReceiverCount; n++) {
        expect(defaultReceiverLayout(court, count: n), hasLength(n));
      }
    });

    test('give every receiver a unique id and name', () {
      for (var n = minReceiverCount; n <= maxReceiverCount; n++) {
        final layout = defaultReceiverLayout(court, count: n);
        expect(layout.map((r) => r.id).toSet(), hasLength(n));
        expect(layout.map((r) => r.name).toSet(), hasLength(n));
      }
    });

    test('place every receiver outside the playing area', () {
      // Anchors are mounted off-court; none may land on the floor of play at
      // any count.
      final playingArea =
          Rect.fromLTWH(0, 0, court.widthMeters, court.heightMeters);

      for (var n = minReceiverCount; n <= maxReceiverCount; n++) {
        for (final r in defaultReceiverLayout(court, count: n)) {
          expect(playingArea.contains(Offset(r.x, r.y)), isFalse,
              reason: '${r.name} is inside the court in the $n-anchor layout');
        }
      }
    });

    test('the triangle spans both ends and both touchlines', () {
      // Three anchors are the geometric minimum. They must still surround the
      // court's centre, otherwise every fix is an extrapolation.
      final layout = defaultReceiverLayout(court, count: 3);
      final xs = layout.map((r) => r.x);
      final ys = layout.map((r) => r.y);

      expect(xs.reduce((a, b) => a < b ? a : b), lessThan(0));
      expect(xs.reduce((a, b) => a > b ? a : b),
          greaterThan(court.widthMeters));
      expect(ys.reduce((a, b) => a < b ? a : b), lessThan(0));
      expect(ys.reduce((a, b) => a > b ? a : b),
          greaterThan(court.heightMeters));
    });

    test('the square is exactly the four corners', () {
      final layout = defaultReceiverLayout(court, count: 4);
      final corners = layout.map((r) => (r.x, r.y)).toSet();

      expect(corners, {
        (-1.2, -1.2),
        (41.2, -1.2),
        (41.2, 21.2),
        (-1.2, 21.2),
      });
    });

    test('the five-anchor layout is the square plus one touchline midpoint',
        () {
      final square = defaultReceiverLayout(court, count: 4)
          .map((r) => (r.x, r.y))
          .toSet();
      final five =
          defaultReceiverLayout(court, count: 5).map((r) => (r.x, r.y)).toSet();

      expect(five, containsAll(square));
      expect(five.difference(square), {(court.widthMeters / 2, -1.2)});
    });

    test('the ring adds a midpoint on each touchline', () {
      final six =
          defaultReceiverLayout(court, count: 6).map((r) => (r.x, r.y)).toSet();

      expect(six, contains((court.widthMeters / 2, -1.2)));
      expect(six, contains((court.widthMeters / 2, 21.2)));
    });

    test('every count keeps the anchors spread across the hall', () {
      // A cell whose anchors bunch together positions poorly, so the widest
      // baseline must stay comparable to the court itself at every count.
      for (var n = minReceiverCount; n <= maxReceiverCount; n++) {
        final layout = defaultReceiverLayout(court, count: n);
        var widest = 0.0;
        for (var i = 0; i < layout.length; i++) {
          for (var j = i + 1; j < layout.length; j++) {
            final d = layout[i].distanceTo(layout[j]);
            if (d > widest) widest = d;
          }
        }
        expect(widest, greaterThan(court.widthMeters),
            reason: 'the $n-anchor layout has too short a baseline');
      }
    });

    test('honour the margin and mounting height they are given', () {
      final layout = defaultReceiverLayout(court,
          count: 4, margin: 3.0, mountHeight: 5.5);

      expect(layout.every((r) => r.z == 5.5), isTrue);
      expect(layout.map((r) => r.x), everyElement(anyOf(-3.0, 43.0)));
    });

    test('clamp a count outside the supported range', () {
      expect(defaultReceiverLayout(court, count: 1), hasLength(minReceiverCount));
      expect(
          defaultReceiverLayout(court, count: 99), hasLength(maxReceiverCount));
    });
  });

  group('changing the receiver count', () {
    test('defaults to the six-anchor ring', () {
      final state = readState(makeContainer());
      expect(state.receiverCount, 6);
      expect(state.layoutShape, ReceiverLayoutShape.ring);
    });

    test('re-applies the preset for the new count', () {
      final c = makeContainer();
      controllerOf(c).setReceiverCount(3);

      final state = readState(c);
      expect(state.receivers, hasLength(3));
      expect(state.layoutShape, ReceiverLayoutShape.triangle);
      expect(state.receivers, defaultReceiverLayout(state.court, count: 3));
      expect(allOutsideCourt(state), isTrue);
    });

    test('is clamped to the supported range', () {
      final c = makeContainer();

      controllerOf(c).setReceiverCount(0);
      expect(readState(c).receiverCount, minReceiverCount);

      controllerOf(c).setReceiverCount(50);
      expect(readState(c).receiverCount, maxReceiverCount);
    });

    test('clears the selection, which may name a removed receiver', () {
      final c = makeContainer();
      controllerOf(c).select(readState(c).receivers.last.id);

      controllerOf(c).setReceiverCount(3);

      expect(readState(c).selectedReceiver, isNull);
    });

    test('leaves placement untouched when the count does not change', () {
      final c = makeContainer();
      controllerOf(c).moveReceiver(readState(c).receivers.first.id, x: 99);
      final before = readState(c).receivers;

      controllerOf(c).setReceiverCount(6);

      expect(readState(c).receivers, before);
    });

    test('reset restores the preset for the current count', () {
      final c = makeContainer();
      controllerOf(c).setReceiverCount(4);
      controllerOf(c).moveReceiver(readState(c).receivers.first.id, x: 99);

      controllerOf(c).resetLayout();

      final state = readState(c);
      expect(state.receivers, defaultReceiverLayout(state.court, count: 4));
    });
  });

  group('settings feed generated layouts', () {
    test('a new layout uses the configured height and clearance', () {
      final c = makeContainer();
      c.read(appSettingsProvider.notifier).setReceiverMountHeightMeters(3.6);
      c.read(appSettingsProvider.notifier).setReceiverMarginMeters(2.5);

      controllerOf(c).resetLayout();

      final state = readState(c);
      expect(state.receivers.every((r) => r.z == 3.6), isTrue);
      expect(state.receivers.first.x, -2.5);
    });

    test('changing the defaults does not move anchors already placed', () {
      // Settings describe how the *next* layout is generated. Silently
      // relocating anchors an operator has surveyed would be worse than
      // useless — it would invalidate their measurements without telling them.
      final c = makeContainer();
      final before = readState(c).receivers;

      c.read(appSettingsProvider.notifier).setReceiverMountHeightMeters(9.0);

      expect(readState(c).receivers, before);
    });
  });
}
