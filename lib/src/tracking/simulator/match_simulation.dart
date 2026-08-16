import 'dart:math' as math;

import '../../domain/domain.dart';
import 'simulated_squad.dart';

/// Deterministic, role-based movement for a simulated handball match.
///
/// Pure Dart on purpose: no Flutter, no timers, no streams. The simulation is
/// driven by explicit `advance(dtMicros:)` calls, which makes it exactly
/// reproducible for a given seed, testable without pumping a widget tree, and
/// reusable from a headless process. Wall-clock scheduling lives in
/// `SimulatorTrackingSource`.
///
/// ## The motion model
///
/// Each player steers toward a target that is expressed as an **offset from a
/// moving anchor**, not as an absolute point. The anchor is the player's role
/// position, shifted along the court by the current play phase; the offset is
/// resampled every few seconds inside the role's wander ellipse. Because the
/// offset rides on the anchor, the whole formation slides up and down the
/// court smoothly as play swings between ends, rather than snapping when a
/// new target is drawn.
///
/// Steering is acceleration-limited: velocity moves toward the desired
/// velocity by at most [_maxAccelerationMps2] × dt per step. This is what
/// keeps trajectories smooth and — more importantly — keeps derived speed and
/// acceleration physically plausible, so the Phase 9 analytics are exercised
/// with realistic input rather than with teleporting dots.
class MatchSimulation {
  final Court court;
  final SimulatedSquad squad;

  /// Seed for every random decision, so a given seed always replays the same
  /// match.
  final int seed;

  /// Period of one full attack/defence swing, in seconds.
  final double playPhasePeriodSeconds;

  /// Human sprint acceleration ceiling, m/s². Field sports peak around
  /// 5–7 m/s²; above that the trajectories stop looking like people.
  static const double _maxAccelerationMps2 = 6.0;

  /// Time constant used to ease into a target instead of overshooting it.
  static const double _arrivalSeconds = 0.55;

  /// Players stay this far inside the sidelines, in metres.
  static const double _courtInsetMeters = 0.3;

  /// Peak displacement of the formation from its neutral position, as a
  /// fraction of court length.
  static const double _playSwingFraction = 0.28;

  final math.Random _random;
  final List<_Body> _bodies = [];

  int _elapsedMicros = 0;

  MatchSimulation({
    required this.court,
    required this.squad,
    this.seed = 20260816,
    this.playPhasePeriodSeconds = 34.0,
  }) : _random = math.Random(seed) {
    for (final participant in squad.participants) {
      final anchor = anchorFor(participant, 0.0);
      final body = _Body(participant: participant, x: anchor.$1, y: anchor.$2);
      _retarget(body);
      // Stagger the first retarget so the squad does not move in lockstep.
      body.retargetInSeconds *= _random.nextDouble();
      _bodies.add(body);
    }
  }

  /// Simulated time consumed so far.
  Duration get elapsed => Duration(microseconds: _elapsedMicros);

  /// Where play currently is, in `-1..1`: `-1` at the home team's own goal,
  /// `+1` at the away team's.
  double get playPhase =>
      math.sin(2 * math.pi * (_elapsedMicros / 1e6) / playPhasePeriodSeconds);

  /// The role anchor for [participant] at play [phase], in world metres.
  ///
  /// Roles are declared in a team-local frame that attacks `+x`; the away
  /// team is that frame rotated 180° about the court centre. The phase shift
  /// is applied *before* the rotation and with opposite sign per team, so
  /// that when one side attacks the other retreats — both formations travel
  /// the same way down the court, which is what a real possession looks like.
  (double, double) anchorFor(SimulatedParticipant participant, double phase) {
    final role = participant.role;
    final localPhase =
        participant.team == SimulatedTeam.home ? phase : -phase;
    final shift =
        localPhase * role.advanceFactor * _playSwingFraction * court.widthMeters;

    final localX = role.homeX * court.widthMeters + shift;
    final localY = role.homeY * court.heightMeters;

    final x = participant.team == SimulatedTeam.home
        ? localX
        : court.widthMeters - localX;
    final y = participant.team == SimulatedTeam.home
        ? localY
        : court.heightMeters - localY;

    return (
      x.clamp(_courtInsetMeters, court.widthMeters - _courtInsetMeters),
      y.clamp(_courtInsetMeters, court.heightMeters - _courtInsetMeters),
    );
  }

  /// Advances every player by [dtMicros] and returns the resulting frame,
  /// stamped [timestampMicros].
  ///
  /// The caller supplies the timestamp rather than the simulation deriving
  /// one, so that simulated time and the wall-clock instant a frame is
  /// published stay the concern of whoever schedules the ticks.
  PositionFrame advance({
    required int dtMicros,
    required int timestampMicros,
  }) {
    assert(dtMicros > 0, 'dtMicros must be positive');

    _elapsedMicros += dtMicros;
    final dt = dtMicros / 1e6;
    final phase = playPhase;

    final samples = <PositionSample>[];
    for (final body in _bodies) {
      _step(body, dt, phase);
      samples.add(
        PositionSample(
          timestampMicros: timestampMicros,
          tagId: body.participant.tagId,
          x: body.x,
          y: body.y,
          confidence: _confidenceAt(body.x, body.y),
        ),
      );
    }

    return PositionFrame(
      timestampMicros: timestampMicros,
      samples: samples,
    );
  }

  void _step(_Body body, double dt, double phase) {
    body.retargetInSeconds -= dt;
    if (body.retargetInSeconds <= 0) _retarget(body);

    final anchor = anchorFor(body.participant, phase);
    final targetX = anchor.$1 + body.offsetX;
    final targetY = anchor.$2 + body.offsetY;

    final toTargetX = targetX - body.x;
    final toTargetY = targetY - body.y;
    final distance = math.sqrt(toTargetX * toTargetX + toTargetY * toTargetY);

    // Desired velocity: head straight at the target, easing off over the last
    // stride so the player settles instead of oscillating around it.
    var desiredX = 0.0;
    var desiredY = 0.0;
    if (distance > 1e-6) {
      final speed = math.min(
        body.participant.role.maxSpeedMps,
        distance / _arrivalSeconds,
      );
      desiredX = toTargetX / distance * speed;
      desiredY = toTargetY / distance * speed;
    }

    // Acceleration-limited approach to the desired velocity.
    var dvx = desiredX - body.vx;
    var dvy = desiredY - body.vy;
    final dvMagnitude = math.sqrt(dvx * dvx + dvy * dvy);
    final maxDv = _maxAccelerationMps2 * dt;
    if (dvMagnitude > maxDv && dvMagnitude > 0) {
      dvx = dvx / dvMagnitude * maxDv;
      dvy = dvy / dvMagnitude * maxDv;
    }

    body.vx += dvx;
    body.vy += dvy;
    body.x += body.vx * dt;
    body.y += body.vy * dt;

    // Keep everyone on the floor of play. Zeroing the offending velocity
    // component avoids a player grinding along a wall at full speed.
    final maxX = court.widthMeters - _courtInsetMeters;
    final maxY = court.heightMeters - _courtInsetMeters;
    if (body.x < _courtInsetMeters) {
      body.x = _courtInsetMeters;
      body.vx = 0;
    } else if (body.x > maxX) {
      body.x = maxX;
      body.vx = 0;
    }
    if (body.y < _courtInsetMeters) {
      body.y = _courtInsetMeters;
      body.vy = 0;
    } else if (body.y > maxY) {
      body.y = maxY;
      body.vy = 0;
    }
  }

  /// Draws a fresh wander offset inside the role's ellipse and schedules the
  /// next redraw.
  void _retarget(_Body body) {
    final role = body.participant.role;
    // Uniform-ish point in an ellipse: random direction, square-rooted radius
    // so targets do not cluster at the centre.
    final angle = _random.nextDouble() * 2 * math.pi;
    final radius = math.sqrt(_random.nextDouble());
    body.offsetX = math.cos(angle) * radius * role.rangeX * court.widthMeters;
    body.offsetY = math.sin(angle) * radius * role.rangeY * court.heightMeters;
    body.retargetInSeconds = 1.5 + _random.nextDouble() * 2.5;
  }

  /// Synthetic positioning quality.
  ///
  /// Real UWB confidence will come from anchor geometry (GDOP), ranging
  /// residuals and the number of contributing receivers. Standing in for that
  /// here: quality is best in the middle of the anchor ring and degrades
  /// toward the corners, which is the shape the real value has. Consumers
  /// must treat it as a hint, never as truth.
  double _confidenceAt(double x, double y) {
    final halfWidth = court.widthMeters / 2;
    final halfHeight = court.heightMeters / 2;
    final nx = (x - halfWidth) / halfWidth;
    final ny = (y - halfHeight) / halfHeight;
    final normalised = math.sqrt(nx * nx + ny * ny) / math.sqrt2;
    return (1.0 - 0.18 * normalised).clamp(0.0, 1.0);
  }
}

/// Mutable per-player integration state. Private: the simulation's only
/// public output is immutable [PositionFrame]s.
class _Body {
  final SimulatedParticipant participant;

  double x;
  double y;
  double vx = 0;
  double vy = 0;

  /// Wander target, relative to the player's current role anchor.
  double offsetX = 0;
  double offsetY = 0;

  double retargetInSeconds = 0;

  _Body({required this.participant, required this.x, required this.y});
}
