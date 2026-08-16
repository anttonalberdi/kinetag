import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'device_connection_state.dart';

/// A UWB receiver/anchor placed around the playing area.
///
/// Position is stored as **real-world coordinates in metres**, in the same
/// frame as the court: `(0,0)` is the court's top-left corner. Receivers are
/// routinely placed outside the playing area, so negative coordinates and
/// coordinates beyond the court extent are valid and expected.
///
/// Inter-receiver distances are intentionally *not* stored. They are derived
/// on demand via [distanceTo]; storing them would create a second source of
/// truth that could disagree with the positions after a drag or a numeric
/// edit.
@immutable
class Receiver {
  final String id;
  final String name;

  /// X coordinate in metres.
  final double x;

  /// Y coordinate in metres.
  final double y;

  /// Mounting height above the floor, in metres.
  final double z;

  final DeviceConnectionState connectionState;

  /// Reserved for future hardware health data (RSSI, firmware, clock drift).
  /// Kept as an open map so hardware integration does not force a schema
  /// migration for every new diagnostic field.
  final Map<String, dynamic> health;

  const Receiver({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    this.z = 2.4,
    this.connectionState = DeviceConnectionState.unknown,
    this.health = const {},
  });

  bool get isConnected => connectionState == DeviceConnectionState.connected;

  /// Straight-line 3D distance to [other], in metres.
  ///
  /// UWB ranging measures true line-of-sight distance, so mounting height
  /// genuinely matters: two anchors 20 m apart on the floor plan but 3 m
  /// apart in height are ~20.22 m apart in reality. This is the distance
  /// used for anchor-geometry setup.
  double distanceTo(Receiver other) {
    final dx = other.x - x;
    final dy = other.y - y;
    final dz = other.z - z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Distance to [other] ignoring height, in metres.
  ///
  /// Useful for reasoning about the floor-plan layout shown in the setup view.
  double planarDistanceTo(Receiver other) {
    final dx = other.x - x;
    final dy = other.y - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Receiver copyWith({
    String? id,
    String? name,
    double? x,
    double? y,
    double? z,
    DeviceConnectionState? connectionState,
    Map<String, dynamic>? health,
  }) =>
      Receiver(
        id: id ?? this.id,
        name: name ?? this.name,
        x: x ?? this.x,
        y: y ?? this.y,
        z: z ?? this.z,
        connectionState: connectionState ?? this.connectionState,
        health: health ?? this.health,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'x': x,
        'y': y,
        'z': z,
        'connectionState': connectionState.name,
        'health': health,
      };

  factory Receiver.fromJson(Map<String, dynamic> json) => Receiver(
        id: json['id'] as String,
        name: json['name'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num).toDouble(),
        connectionState:
            DeviceConnectionState.values.byName(json['connectionState'] as String),
        health: Map<String, dynamic>.from(
            json['health'] as Map? ?? const <String, dynamic>{}),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Receiver &&
          other.id == id &&
          other.name == name &&
          other.x == x &&
          other.y == y &&
          other.z == z &&
          other.connectionState == connectionState;

  @override
  int get hashCode => Object.hash(id, name, x, y, z, connectionState);

  @override
  String toString() =>
      'Receiver($name, x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}, '
      'z=${z.toStringAsFixed(2)})';
}
