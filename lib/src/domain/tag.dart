import 'package:meta/meta.dart';

import 'device_connection_state.dart';

/// A physical UWB tag worn by a player.
///
/// Tags are deliberately modelled independently of [Player]. A tag is a piece
/// of inventory that may be worn by different players in different sessions,
/// and a player may wear two tags at once (see `TagAssignment`). Conflating
/// the two would make it impossible to re-assign hardware between sessions
/// without rewriting player history.
@immutable
class Tag {
  /// Stable application-level identifier.
  final String id;

  /// Identifier burned into the physical hardware (e.g. UWB short address).
  /// For simulated tags this is a synthetic value.
  final String hardwareId;

  final String name;

  final DeviceConnectionState connectionState;

  /// Battery charge 0..100, or null when unknown (e.g. simulated tags).
  final double? batteryPercent;

  /// Reserved for future status data (firmware version, ranging error rate).
  final Map<String, dynamic> status;

  const Tag({
    required this.id,
    required this.hardwareId,
    required this.name,
    this.connectionState = DeviceConnectionState.unknown,
    this.batteryPercent,
    this.status = const {},
  });

  bool get isConnected => connectionState == DeviceConnectionState.connected;

  Tag copyWith({
    String? id,
    String? hardwareId,
    String? name,
    DeviceConnectionState? connectionState,
    double? batteryPercent,
    Map<String, dynamic>? status,
  }) =>
      Tag(
        id: id ?? this.id,
        hardwareId: hardwareId ?? this.hardwareId,
        name: name ?? this.name,
        connectionState: connectionState ?? this.connectionState,
        batteryPercent: batteryPercent ?? this.batteryPercent,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hardwareId': hardwareId,
        'name': name,
        'connectionState': connectionState.name,
        'batteryPercent': batteryPercent,
        'status': status,
      };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id'] as String,
        hardwareId: json['hardwareId'] as String,
        name: json['name'] as String,
        connectionState: DeviceConnectionState.values
            .byName(json['connectionState'] as String),
        batteryPercent: (json['batteryPercent'] as num?)?.toDouble(),
        status: Map<String, dynamic>.from(
            json['status'] as Map? ?? const <String, dynamic>{}),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          other.id == id &&
          other.hardwareId == hardwareId &&
          other.name == name &&
          other.connectionState == connectionState &&
          other.batteryPercent == batteryPercent;

  @override
  int get hashCode =>
      Object.hash(id, hardwareId, name, connectionState, batteryPercent);

  @override
  String toString() => 'Tag($name, hw=$hardwareId)';
}
