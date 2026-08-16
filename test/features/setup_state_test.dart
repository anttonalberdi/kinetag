import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/features/setup/setup_state.dart';

/// Builds an isolated container so each test starts from the default layout.
({ProviderContainer container, SetupController controller}) makeController() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return (
    container: container,
    controller: container.read(setupControllerProvider.notifier),
  );
}

SetupState readState(ProviderContainer c) => c.read(setupControllerProvider);

void main() {
  group('default layout', () {
    test('places six receivers around a handball court', () {
      final c = makeController();
      final state = readState(c.container);

      expect(state.receivers, hasLength(6));
      expect(state.court.widthMeters, 40.0);
      expect(state.court.heightMeters, 20.0);
    });

    test('all receivers sit outside the playing area', () {
      // Anchors are mounted off-court; none should land on the floor of play.
      final state = readState(makeController().container);
      final court = Rect.fromLTWH(
          0, 0, state.court.widthMeters, state.court.heightMeters);

      for (final r in state.receivers) {
        expect(
          court.contains(Offset(r.x, r.y)),
          isFalse,
          reason: '${r.name} at (${r.x}, ${r.y}) is inside the court',
        );
      }
    });

    test('receivers are mounted above head height', () {
      for (final r in readState(makeController().container).receivers) {
        expect(r.z, greaterThan(2.0));
      }
    });

    test('receiver ids and names are unique', () {
      final receivers = readState(makeController().container).receivers;
      expect(receivers.map((r) => r.id).toSet(), hasLength(6));
      expect(receivers.map((r) => r.name).toSet(), hasLength(6));
    });
  });

  group('selection', () {
    test('selects the receiver under the pointer', () {
      final c = makeController();
      final target = readState(c.container).receivers[2];

      final hit = c.controller.selectAt(Offset(target.x, target.y), 0.5);

      expect(hit, isTrue);
      expect(readState(c.container).selectedReceiverId, target.id);
    });

    test('clears the selection when clicking empty space', () {
      final c = makeController();
      final target = readState(c.container).receivers.first;
      c.controller.select(target.id);

      // Court centre: far from every perimeter receiver.
      final hit = c.controller.selectAt(const Offset(20, 10), 0.5);

      expect(hit, isFalse);
      expect(readState(c.container).selectedReceiver, isNull);
    });

    test('picks the nearest receiver when two are within tolerance', () {
      final c = makeController();
      final receivers = readState(c.container).receivers;
      // Place two receivers close together, then click nearer to the second.
      c.controller.moveReceiver(receivers[0].id, x: 10, y: 10);
      c.controller.moveReceiver(receivers[1].id, x: 11, y: 10);

      c.controller.selectAt(const Offset(10.9, 10), 2.0);

      expect(readState(c.container).selectedReceiverId, receivers[1].id);
    });

    test('respects the hit tolerance', () {
      final c = makeController();
      final target = readState(c.container).receivers.first;

      // 3 m away with a 0.5 m tolerance must miss.
      expect(
        c.controller.selectAt(Offset(target.x + 3, target.y), 0.5),
        isFalse,
      );
    });
  });

  group('dragging', () {
    test('moves the receiver and updates its world coordinates', () {
      final c = makeController();
      final target = readState(c.container).receivers.first;

      c.controller.beginDrag(Offset(target.x, target.y), 0.5);
      c.controller.updateDrag(const Offset(5, 5));
      c.controller.endDrag();

      final moved = readState(c.container).selectedReceiver!;
      expect(moved.id, target.id);
      expect(moved.x, closeTo(5.0, 1e-9));
      expect(moved.y, closeTo(5.0, 1e-9));
    });

    test('preserves the grab offset so the marker does not jump', () {
      // Grabbing a marker 0.4 m off-centre must keep that offset for the
      // whole drag, otherwise the receiver snaps under the cursor.
      final c = makeController();
      final target = readState(c.container).receivers.first;
      final grabPoint = Offset(target.x + 0.4, target.y + 0.3);

      c.controller.beginDrag(grabPoint, 1.0);
      c.controller.updateDrag(const Offset(12, 8));

      final moved = readState(c.container).selectedReceiver!;
      expect(moved.x, closeTo(12 - 0.4, 1e-9));
      expect(moved.y, closeTo(8 - 0.3, 1e-9));
    });

    test('dragging empty space selects nothing and moves nothing', () {
      final c = makeController();
      final before = readState(c.container).receivers;

      final started = c.controller.beginDrag(const Offset(20, 10), 0.5);
      c.controller.updateDrag(const Offset(25, 12));

      expect(started, isFalse);
      expect(readState(c.container).receivers, before);
    });

    test('preserves height while dragging in the XY plane', () {
      final c = makeController();
      final target = readState(c.container).receivers.first;
      final originalZ = target.z;

      c.controller.beginDrag(Offset(target.x, target.y), 0.5);
      c.controller.updateDrag(const Offset(3, 3));

      expect(readState(c.container).selectedReceiver!.z, originalZ);
    });

    test('clamps a drag to the visible world', () {
      const visible = Rect.fromLTRB(-5, -5, 45, 25);
      final clamped = SetupController.clampToVisibleWorld(
          const Offset(100, -80), visible);

      expect(clamped, const Offset(45, -5));
    });
  });

  group('numeric editing', () {
    test('sets X, Y and Z independently', () {
      final c = makeController();
      final target = readState(c.container).receivers.first;

      c.controller.moveReceiver(target.id, x: -1.20);
      c.controller.moveReceiver(target.id, y: -0.80);
      c.controller.moveReceiver(target.id, z: 2.40);

      final r = readState(c.container)
          .receivers
          .firstWhere((r) => r.id == target.id);
      expect(r.x, -1.20);
      expect(r.y, -0.80);
      expect(r.z, 2.40);
    });

    test('editing one receiver leaves the others untouched', () {
      final c = makeController();
      final receivers = readState(c.container).receivers;
      final others = receivers.sublist(1);

      c.controller.moveReceiver(receivers.first.id, x: 99);

      expect(readState(c.container).receivers.sublist(1), others);
    });

    test('accepts coordinates outside the court', () {
      final c = makeController();
      final target = readState(c.container).receivers.first;

      c.controller.moveReceiver(target.id, x: -4.5, y: 24.0);

      final r = readState(c.container)
          .receivers
          .firstWhere((r) => r.id == target.id);
      expect(r.x, -4.5);
      expect(r.y, 24.0);
    });
  });

  group('derived distances', () {
    test('are empty with no selection', () {
      expect(readState(makeController().container).distancesFromSelection,
          isEmpty);
    });

    test('list every other receiver, nearest first', () {
      final c = makeController();
      c.controller.select(readState(c.container).receivers.first.id);

      final distances = readState(c.container).distancesFromSelection;

      expect(distances, hasLength(5));
      for (var i = 1; i < distances.length; i++) {
        expect(distances[i].distanceMeters,
            greaterThanOrEqualTo(distances[i - 1].distanceMeters));
      }
    });

    test('update immediately when a receiver is moved', () {
      // The key guarantee: distances are derived, never stored, so they can
      // never go stale after a drag or a numeric edit.
      final c = makeController();
      final receivers = readState(c.container).receivers;
      c.controller.select(receivers.first.id);

      final before = readState(c.container)
          .distancesFromSelection
          .firstWhere((d) => d.receiver.id == receivers[1].id)
          .distanceMeters;

      c.controller.moveReceiver(receivers[1].id, x: 200);

      final after = readState(c.container)
          .distancesFromSelection
          .firstWhere((d) => d.receiver.id == receivers[1].id)
          .distanceMeters;

      expect(after, greaterThan(before));
    });

    test('account for height difference', () {
      final c = makeController();
      final receivers = readState(c.container).receivers;

      // Put two receivers on the same spot, 3 m apart vertically.
      c.controller.moveReceiver(receivers[0].id, x: 0, y: 0, z: 0);
      c.controller.moveReceiver(receivers[1].id, x: 0, y: 0, z: 3);
      c.controller.select(receivers[0].id);

      final d = readState(c.container)
          .distancesFromSelection
          .firstWhere((d) => d.receiver.id == receivers[1].id);
      expect(d.distanceMeters, closeTo(3.0, 1e-9));
    });
  });

  group('layout reset', () {
    test('restores defaults and clears the selection', () {
      final c = makeController();
      final target = readState(c.container).receivers.first;
      c.controller.moveReceiver(target.id, x: 99, y: 99);
      c.controller.select(target.id);

      c.controller.resetLayout();

      final state = readState(c.container);
      expect(state.selectedReceiver, isNull);
      expect(state.receivers.first.x, isNot(99));
      expect(state.receivers, defaultReceiverLayout(state.court));
    });
  });
}
