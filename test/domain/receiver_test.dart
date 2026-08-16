import 'package:flutter_test/flutter_test.dart';
import 'package:kinetag/src/domain/domain.dart';

void main() {
  group('Receiver distances', () {
    test('3D distance accounts for mounting height', () {
      const a = Receiver(id: 'a', name: 'RX-01', x: 0, y: 0, z: 0);
      const b = Receiver(id: 'b', name: 'RX-02', x: 3, y: 4, z: 12);

      // 3-4-5 triangle in the plane, then 5-12-13 with height.
      expect(a.distanceTo(b), closeTo(13.0, 1e-9));
      expect(a.planarDistanceTo(b), closeTo(5.0, 1e-9));
    });

    test('distance is symmetric', () {
      const a = Receiver(id: 'a', name: 'RX-01', x: -1.2, y: -0.8, z: 2.4);
      const b = Receiver(id: 'b', name: 'RX-02', x: 41.2, y: 20.8, z: 2.4);

      expect(a.distanceTo(b), closeTo(b.distanceTo(a), 1e-12));
    });

    test('distance to self is zero', () {
      const a = Receiver(id: 'a', name: 'RX-01', x: 12.5, y: 7.5, z: 2.4);
      expect(a.distanceTo(a), 0.0);
    });

    test('equal-height receivers have equal 3D and planar distance', () {
      const a = Receiver(id: 'a', name: 'RX-01', x: 0, y: 0, z: 2.4);
      const b = Receiver(id: 'b', name: 'RX-02', x: 40, y: 20, z: 2.4);

      expect(a.distanceTo(b), closeTo(a.planarDistanceTo(b), 1e-12));
    });

    test('corner-to-corner of a handball court is ~44.72 m', () {
      const a = Receiver(id: 'a', name: 'RX-01', x: 0, y: 0, z: 0);
      const b = Receiver(id: 'b', name: 'RX-02', x: 40, y: 20, z: 0);

      expect(a.distanceTo(b), closeTo(44.7213595, 1e-6));
    });
  });

  group('Receiver state', () {
    test('accepts coordinates outside the playing area', () {
      // Receivers are routinely mounted off-court; negative coordinates and
      // coordinates beyond the court extent must be representable.
      const r = Receiver(id: 'a', name: 'RX-01', x: -5.0, y: 24.5, z: 3.1);
      expect(r.x, -5.0);
      expect(r.y, 24.5);
    });

    test('copyWith updates only the named fields', () {
      const r = Receiver(id: 'a', name: 'RX-01', x: 1, y: 2, z: 3);
      final moved = r.copyWith(x: 10.5);

      expect(moved.x, 10.5);
      expect(moved.y, 2);
      expect(moved.z, 3);
      expect(moved.id, 'a');
      expect(moved.name, 'RX-01');
    });

    test('isConnected reflects connection state', () {
      const r = Receiver(id: 'a', name: 'RX-01', x: 0, y: 0);
      expect(r.isConnected, isFalse); // unknown by default
      expect(
        r.copyWith(connectionState: DeviceConnectionState.connected)
            .isConnected,
        isTrue,
      );
    });

    test('survives a JSON round trip', () {
      const r = Receiver(
        id: 'rx-1',
        name: 'RX-01',
        x: -1.2,
        y: -0.8,
        z: 2.4,
        connectionState: DeviceConnectionState.connected,
      );
      expect(Receiver.fromJson(r.toJson()), r);
    });
  });
}
