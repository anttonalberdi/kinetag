import 'package:meta/meta.dart';

/// The sport a [Court] is laid out for.
///
/// Kinetag starts with handball; other sports change only the court dimensions
/// and markings, not the coordinate system or tracking pipeline.
enum SportType {
  handball('Handball');

  const SportType(this.displayName);

  final String displayName;
}

/// A playing area described in real-world metres.
///
/// The playing area always spans `(0,0)` to `(widthMeters, heightMeters)`.
/// Receivers may legitimately sit outside these bounds — see
/// `CourtViewTransform` for how a larger surrounding region is displayed.
@immutable
class Court {
  final String id;
  final String name;
  final SportType sport;

  /// Playing-area extent along X, in metres.
  final double widthMeters;

  /// Playing-area extent along Y, in metres.
  final double heightMeters;

  const Court({
    required this.id,
    required this.name,
    required this.sport,
    required this.widthMeters,
    required this.heightMeters,
  });

  /// A regulation handball court: 40 m along X, 20 m along Y.
  factory Court.handball({
    String id = 'court-handball-default',
    String name = 'Handball Court',
  }) =>
      Court(
        id: id,
        name: name,
        sport: SportType.handball,
        widthMeters: 40.0,
        heightMeters: 20.0,
      );

  Court copyWith({
    String? id,
    String? name,
    SportType? sport,
    double? widthMeters,
    double? heightMeters,
  }) =>
      Court(
        id: id ?? this.id,
        name: name ?? this.name,
        sport: sport ?? this.sport,
        widthMeters: widthMeters ?? this.widthMeters,
        heightMeters: heightMeters ?? this.heightMeters,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sport': sport.name,
        'widthMeters': widthMeters,
        'heightMeters': heightMeters,
      };

  factory Court.fromJson(Map<String, dynamic> json) => Court(
        id: json['id'] as String,
        name: json['name'] as String,
        sport: SportType.values.byName(json['sport'] as String),
        widthMeters: (json['widthMeters'] as num).toDouble(),
        heightMeters: (json['heightMeters'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Court &&
          other.id == id &&
          other.name == name &&
          other.sport == sport &&
          other.widthMeters == widthMeters &&
          other.heightMeters == heightMeters;

  @override
  int get hashCode => Object.hash(id, name, sport, widthMeters, heightMeters);

  @override
  String toString() =>
      'Court($name, ${widthMeters}x${heightMeters}m, ${sport.displayName})';
}
