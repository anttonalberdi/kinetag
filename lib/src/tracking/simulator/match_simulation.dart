import 'dart:math' as math;

import '../../domain/domain.dart';
import 'role_movement.dart';
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
///
/// ## The goal areas
///
/// Only a goalkeeper may stand in the 6 m zone; in handball that is a rule,
/// not a tendency, so the simulation enforces it rather than merely making it
/// unlikely. Outfield players are *aimed* [goalAreaAimClearanceMeters] outside
/// [GoalArea] and *held* [goalAreaClearanceMeters] outside it, so ordinary
/// steering does the turning and the clamp is only ever a backstop; they skim
/// the line the way a wing does instead of grinding into it. A heatmap of a
/// simulated session therefore has the two D-shaped holes a real one has, and
/// anything downstream that comes to depend on that — shot-zone analysis, say
/// — is being fed a floor plan that means something.
///
/// ## The bench
///
/// Whoever the squad has not fielded is parked at a fixed seat just outside a
/// sideline (see [benchSeatAt]). Substitutes do not wander, do not follow the
/// play phase, and are not held inside the court — a substitute's tag keeps
/// reporting, so the simulator keeps emitting for it, and the resulting flat
/// track is what tells the analytics downstream that this player was not
/// playing at the time.
///
/// ## Substitutions
///
/// Every [substitutionInterval] each side swaps its longest-serving field
/// player for its longest-waiting substitute, so that over a match the bench
/// empties and refills instead of being a place players are sent to die. The
/// exchange is sequenced the way the rules require: the player coming off
/// jogs to the bench seat first, and only when they have crossed the sideline
/// and reached it does the substitute leave that seat and step on. The two are
/// never on court together, which is the whole point — a simulation that let
/// them overlap would show a side briefly playing with an extra player, and
/// every team metric computed over that window would be quietly wrong.
class MatchSimulation {
  final Court court;
  final SimulatedSquad squad;

  /// Seed for every random decision, so a given seed always replays the same
  /// match.
  final int seed;

  /// Period of one full attack/defence swing, in seconds.
  final double playPhasePeriodSeconds;

  /// How often each side exchanges a field player with a substitute.
  ///
  /// [Duration.zero] keeps the starting line-up on court for the whole match.
  /// A side with an empty bench never substitutes whatever this says, and
  /// goalkeepers are never exchanged — a second keeper on the bench comes on
  /// as an outfield player, the same rule the line-up itself uses.
  final Duration substitutionInterval;

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

  /// How far outside the goal-area line an outfield player is held, in metres.
  ///
  /// Positions are a player's centre, so a small clearance also keeps the dot
  /// drawn for them from overlapping the line it is not allowed to cross.
  static const double goalAreaClearanceMeters = 0.35;

  /// How far outside it they are *aimed*, in metres.
  ///
  /// Wider than the clearance on purpose. The gap between the two is the room
  /// a player has to carry momentum into the line and be turned by ordinary
  /// steering, which is smooth; without it the position clamp would do the
  /// turning, and a clamp is a discontinuity that lands in the data as a
  /// spike of acceleration. Still less than the stride a defender naturally
  /// stands off the line, so nothing is given up in how close play gets.
  static const double goalAreaAimClearanceMeters = 1.1;

  /// How often a side substitutes when nothing says otherwise.
  ///
  /// A minute is roughly what a training game does with a short bench, and it
  /// is short enough that a few minutes of recording exercises the rotation
  /// rather than merely declaring it.
  static const Duration defaultSubstitutionInterval = Duration(minutes: 1);

  /// How close to their seat a player leaving the court must get before the
  /// substitute replacing them may step on, in metres.
  static const double benchArrivalMeters = 0.75;

  /// How far beyond the sideline the bench stands, in metres.
  ///
  /// Absolute rather than a fraction of the court, unlike everything a role
  /// envelope declares: a substitute stands a stride off the line whether the
  /// hall holds a full court or a training pitch.
  static const double benchClearanceMeters = 0.5;

  /// Distance between neighbouring bench seats, in metres. Wide enough that
  /// two substitutes read as two dots on court, close enough to look like
  /// people standing next to each other.
  static const double benchSpacingMeters = 0.9;

  /// Gap between the centre line and the first bench seat, in metres.
  static const double benchCentreGapMeters = 1.0;

  final math.Random _random;
  final GoalArea _goalArea;
  final List<_Body> _bodies = [];

  int _elapsedMicros = 0;
  double _secondsToNextSubstitution = 0;
  int _substitutionCount = 0;

  MatchSimulation({
    required this.court,
    required this.squad,
    this.seed = 20260816,
    this.playPhasePeriodSeconds = 34.0,
    this.substitutionInterval = defaultSubstitutionInterval,
  })  : _random = math.Random(seed),
        _goalArea = GoalArea(court) {
    assert(!substitutionInterval.isNegative, 'an interval cannot run backwards');
    _secondsToNextSubstitution = substitutionInterval.inMicroseconds / 1e6;

    for (final participant in squad.participants) {
      final body = _Body(participant: participant);
      final anchor = _anchorFor(body, 0.0);
      body.x = anchor.$1;
      body.y = anchor.$2;
      // A substitute has nothing to wander toward, and drawing for one would
      // shift every fielded player's wander as well — the bench would change
      // the match instead of only sitting out of it.
      if (body.isFielded) {
        _retarget(body);
        // Stagger the first retarget so the squad does not move in lockstep.
        body.retargetInSeconds *= _random.nextDouble();
      }
      _bodies.add(body);
    }
  }

  /// Simulated time consumed so far.
  Duration get elapsed => Duration(microseconds: _elapsedMicros);

  /// Exchanges completed since the match began, counting each side's
  /// separately.
  int get substitutionCount => _substitutionCount;

  /// Where play currently is, in `-1..1`: `-1` at the home team's own goal,
  /// `+1` at the away team's.
  double get playPhase =>
      math.sin(2 * math.pi * (_elapsedMicros / 1e6) / playPhasePeriodSeconds);

  /// Whether [tagId] is currently playing rather than sitting out.
  ///
  /// Reads the *live* line-up, which is what a substitution changes;
  /// `squad.onCourt` only ever describes who started. A player on their way to
  /// the bench already counts as off, and a substitute waiting for them counts
  /// as on the bench until they actually step on.
  bool isOnCourt(String tagId) {
    for (final body in _bodies) {
      if (body.participant.tagId == tagId) return body.isFielded;
    }
    return false;
  }

  /// Where the [seat]-th substitute of [side] stands, in world metres.
  ///
  /// Benches sit just outside a sideline — home beyond `y = 0`, away beyond
  /// `y = height`, which is the same 180° rotation the role frame uses — and
  /// run from beside the centre line back toward the team's own goal, the way
  /// a hall lays them out. Seats do not move: a substitute is standing, not
  /// playing, and a track that stays put is exactly what should distinguish
  /// them in the analytics afterwards.
  ///
  /// Unlike a role anchor this is not clamped into the playing area — that is
  /// the whole point of it — but it is kept between the goal lines so a deep
  /// bench does not trail off behind the goal.
  (double, double) benchSeatAt(TeamSide side, int seat) {
    final isHome = side == TeamSide.home;
    final halfWidth = court.widthMeters / 2;
    final fromCentre = benchCentreGapMeters + seat * benchSpacingMeters;

    final x = (isHome ? halfWidth - fromCentre : halfWidth + fromCentre)
        .clamp(_courtInsetMeters, court.widthMeters - _courtInsetMeters);
    final y = isHome
        ? -benchClearanceMeters
        : court.heightMeters + benchClearanceMeters;

    return (x, y);
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

    _advanceSubstitutions(dt);

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

  /// The role anchor for [body] at play [phase], in world metres.
  ///
  /// Roles are declared in a team-local frame that attacks `+x`; the away
  /// team is that frame rotated 180° about the court centre. The phase shift
  /// is applied *before* the rotation and with opposite sign per team, so
  /// that when one side attacks the other retreats — both formations travel
  /// the same way down the court, which is what a real possession looks like.
  ///
  /// Reads the body's live slot rather than the participant's starting one: a
  /// substitute who has come on steers to the position they took over, and a
  /// player who has come off steers to the seat they were given.
  (double, double) _anchorFor(_Body body, double phase) {
    final seat = body.benchSeat;
    if (seat != null) return benchSeatAt(body.participant.side, seat);

    final movement = body.movement;
    final isHome = body.participant.side == TeamSide.home;
    final localPhase = isHome ? phase : -phase;
    final shift = localPhase *
        movement.advanceFactor *
        _playSwingFraction *
        court.widthMeters;

    final localX = movement.homeX * court.widthMeters + shift;
    final localY = movement.homeY * court.heightMeters;

    final x = isHome ? localX : court.widthMeters - localX;
    final y = isHome ? localY : court.heightMeters - localY;

    return (
      x.clamp(_courtInsetMeters, court.widthMeters - _courtInsetMeters),
      y.clamp(_courtInsetMeters, court.heightMeters - _courtInsetMeters),
    );
  }

  void _step(_Body body, double dt, double phase) {
    final fielded = body.isFielded;

    if (fielded) {
      body.retargetInSeconds -= dt;
      if (body.retargetInSeconds <= 0) _retarget(body);
    }

    final anchor = _anchorFor(body, phase);
    var targetX = anchor.$1 + body.offsetX;
    var targetY = anchor.$2 + body.offsetY;

    // Steer around the goal area rather than into it: aiming at a legal point
    // is what keeps the position clamp below from having to do any work in the
    // ordinary case, and so keeps trajectories smooth.
    if (fielded && !body.movement.keepsGoal) {
      final legal = _goalArea.pushOut(
        targetX,
        targetY,
        margin: goalAreaAimClearanceMeters,
      );
      targetX = legal.$1;
      targetY = legal.$2;
    }

    final toTargetX = targetX - body.x;
    final toTargetY = targetY - body.y;
    final distance = math.sqrt(toTargetX * toTargetX + toTargetY * toTargetY);

    // Desired velocity: head straight at the target, easing off over the last
    // stride so the player settles instead of oscillating around it.
    var desiredX = 0.0;
    var desiredY = 0.0;
    if (distance > 1e-6) {
      final speed = math.min(
        body.movement.maxSpeedMps,
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

    _keepOutOfGoalArea(body);
    _keepOnCourt(body);
  }

  /// Pushes an outfield player back out of a goal area they have drifted into.
  ///
  /// A safety net rather than the main mechanism — the target is already
  /// legal — so it fires only on momentum carried into the line, and then only
  /// by centimetres. Dropping the inward velocity component matters as much as
  /// moving the player: without it they would be shoved out every frame while
  /// still accelerating in, which reads as juddering along the arc.
  void _keepOutOfGoalArea(_Body body) {
    if (body.movement.keepsGoal) return;
    // Off the playing surface there is no goal area to be in: the bench is
    // outside the sideline, and a player walking to it has already left.
    if (!_isOnPlayingSurface(body.x, body.y)) return;

    final legal = _goalArea.pushOut(
      body.x,
      body.y,
      margin: goalAreaClearanceMeters,
    );
    if (legal.$1 == body.x && legal.$2 == body.y) return;

    final outX = legal.$1 - body.x;
    final outY = legal.$2 - body.y;
    final length = math.sqrt(outX * outX + outY * outY);
    if (length > 1e-9) {
      final unitX = outX / length;
      final unitY = outY / length;
      final inward = body.vx * unitX + body.vy * unitY;
      if (inward < 0) {
        body.vx -= inward * unitX;
        body.vy -= inward * unitY;
      }
    }

    body.x = legal.$1;
    body.y = legal.$2;
  }

  /// Keeps a fielded player on the floor of play.
  ///
  /// Deliberately does nothing for anyone off it: a substitute's seat is
  /// outside the sideline, and clamping would drag the whole bench back over
  /// the line. It also holds off for a substitute who is stepping on until
  /// they are properly inside, because a clamp applied while they are still
  /// crossing would snap them onto the court and put a spike of acceleration
  /// into the data at every substitution.
  void _keepOnCourt(_Body body) {
    if (!body.isFielded) return;

    final maxX = court.widthMeters - _courtInsetMeters;
    final maxY = court.heightMeters - _courtInsetMeters;

    if (!body.heldOnCourt) {
      final inside = body.x >= _courtInsetMeters &&
          body.x <= maxX &&
          body.y >= _courtInsetMeters &&
          body.y <= maxY;
      if (!inside) return;
      body.heldOnCourt = true;
    }

    // Zeroing the offending velocity component avoids a player grinding along
    // a wall at full speed.
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

  bool _isOnPlayingSurface(double x, double y) =>
      x >= 0 && x <= court.widthMeters && y >= 0 && y <= court.heightMeters;

  /// Runs the substitution clock and completes any exchange whose outgoing
  /// player has reached the bench.
  void _advanceSubstitutions(double dt) {
    _completeArrivals();

    if (substitutionInterval == Duration.zero) return;

    _secondsToNextSubstitution -= dt;
    if (_secondsToNextSubstitution > 0) return;

    // Add rather than reset, so the rotation keeps the interval's cadence even
    // if a long step overshoots it.
    _secondsToNextSubstitution += substitutionInterval.inMicroseconds / 1e6;
    for (final side in TeamSide.values) {
      _beginSubstitution(side);
    }
  }

  /// Sends one field player of [side] off and promises their slot to one
  /// substitute.
  ///
  /// Picks the player who has been on longest and the substitute who has waited
  /// longest, which rotates the whole bench through the match without any
  /// randomness — a seed already decides how players move, and it should not
  /// also decide who plays. Ties fall to roster order, the only ranking the
  /// operator has actually expressed.
  void _beginSubstitution(TeamSide side) {
    _Body? outgoing;
    _Body? incoming;

    for (final body in _bodies) {
      if (body.participant.side != side) continue;

      if (body.isFielded) {
        // The keeper is not part of the rotation: a side that exchanged theirs
        // would be playing without one until the replacement arrived.
        if (body.movement.keepsGoal) continue;
        // Nor is somebody who has not finished stepping on: sending them
        // straight back would make the exchange before this one pointless.
        if (!body.heldOnCourt) continue;
        if (outgoing == null || body.slotSinceMicros < outgoing.slotSinceMicros) {
          outgoing = body;
        }
      } else {
        // Only somebody actually sitting down can come on: a player still
        // walking off is not available, and neither is one already promised a
        // slot in an exchange that has not completed.
        if (body.entersFor != null) continue;
        if (!_hasReachedBench(body)) continue;
        if (incoming == null || body.slotSinceMicros < incoming.slotSinceMicros) {
          incoming = body;
        }
      }
    }

    if (outgoing == null || incoming == null) return;

    // The seat the substitute vacates is the seat the outgoing player walks
    // to, so a bench never grows a row: the two swap places, on court and off.
    incoming.entersFor = outgoing;
    incoming.takesSlot = outgoing.movement;

    outgoing.benchSeat = incoming.benchSeat;
    outgoing.movement = RoleMovement.leavingCourt;
    outgoing.heldOnCourt = false;
    outgoing.offsetX = 0;
    outgoing.offsetY = 0;
    outgoing.slotSinceMicros = _elapsedMicros;
  }

  /// Lets a waiting substitute on once the player they replace is off.
  void _completeArrivals() {
    for (final body in _bodies) {
      final leaving = body.entersFor;
      if (leaving == null) continue;
      if (!_hasReachedBench(leaving)) continue;

      // The player coming off has arrived: they are a substitute from here on,
      // and the one who was waiting takes the slot they left.
      leaving.movement = RoleMovement.benched;

      body.entersFor = null;
      body.benchSeat = null;
      body.movement = body.takesSlot!;
      body.takesSlot = null;
      body.slotSinceMicros = _elapsedMicros;
      body.heldOnCourt = false;
      _retarget(body);
      _substitutionCount++;
    }
  }

  /// Whether [body] has left the playing area and reached its bench seat.
  ///
  /// Both halves are load-bearing. Crossing the sideline is what makes the
  /// exchange legal; reaching the seat is what makes it look like one, since
  /// the substitute is standing there and the two should meet before they
  /// trade places.
  bool _hasReachedBench(_Body body) {
    final seat = body.benchSeat;
    if (seat == null) return false;

    if (_isOnPlayingSurface(body.x, body.y)) return false;

    final target = benchSeatAt(body.participant.side, seat);
    final dx = body.x - target.$1;
    final dy = body.y - target.$2;
    return dx * dx + dy * dy <= benchArrivalMeters * benchArrivalMeters;
  }

  /// Draws a fresh wander offset inside the role's ellipse and schedules the
  /// next redraw.
  void _retarget(_Body body) {
    final movement = body.movement;
    // Uniform-ish point in an ellipse: random direction, square-rooted radius
    // so targets do not cluster at the centre.
    final angle = _random.nextDouble() * 2 * math.pi;
    final radius = math.sqrt(_random.nextDouble());
    body.offsetX =
        math.cos(angle) * radius * movement.rangeX * court.widthMeters;
    body.offsetY =
        math.sin(angle) * radius * movement.rangeY * court.heightMeters;
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
///
/// Holds the *live* line-up as well as the physics. The participant it was
/// built from records who started where and never changes, because the squad
/// is shared, compared and rebuilt from the roster; who is on court right now
/// is a fact about this match in progress and belongs here.
class _Body {
  final SimulatedParticipant participant;

  /// The envelope currently being played. Starts as the participant's, becomes
  /// the vacated slot's when this player is substituted on, and
  /// [RoleMovement.leavingCourt] then [RoleMovement.benched] on the way off.
  RoleMovement movement;

  /// Seat currently occupied or being walked to, or null when playing.
  int? benchSeat;

  /// The player this one is waiting to replace, or null when not mid-exchange.
  /// While it is set, this player stays seated however long the wait takes.
  _Body? entersFor;

  /// The envelope [entersFor] will hand over on arrival.
  RoleMovement? takesSlot;

  /// When the current stint — on court or on the bench — began, in simulated
  /// microseconds. Drives who is next off and who is next on.
  int slotSinceMicros = 0;

  /// Whether the court clamp has taken hold. False while a substitute is
  /// stepping on, so that crossing the sideline is a walk rather than a snap.
  bool heldOnCourt;

  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;

  /// Wander target, relative to the player's current role anchor.
  double offsetX = 0;
  double offsetY = 0;

  double retargetInSeconds = 0;

  _Body({required this.participant})
      : movement = participant.movement,
        benchSeat = participant.benchSeat,
        heldOnCourt = participant.isOnCourt;

  /// Whether this player is currently playing rather than seated or walking
  /// off.
  bool get isFielded => benchSeat == null;
}
