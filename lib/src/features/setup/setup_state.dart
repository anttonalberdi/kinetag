import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../domain/domain.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';

/// Fewest receivers that can position a tag in 2D.
///
/// Three ranges intersect at two points, and the ambiguity is resolved by the
/// tag being on the floor of play. It works, but with no redundancy: lose one
/// anchor to an occluded line of sight and positioning stops rather than
/// degrades.
const int minReceiverCount = 3;

/// Most receivers the prototype supports.
///
/// A hard ceiling for now because the layout presets are hand-designed per
/// count. Real halls will want more, at which point the presets become a
/// generated ring rather than a table.
const int maxReceiverCount = 6;

/// The named shape a given receiver count is arranged in.
///
/// Anchor geometry is the dominant limit on UWB accuracy, so the presets are
/// not decoration: each one keeps the anchors spread as widely as the hall
/// allows, because positioning error grows sharply as the anchors bunch
/// together or as the tag leaves the area they enclose.
enum ReceiverLayoutShape {
  /// Two anchors on one touchline's corners, one at the middle of the
  /// opposite touchline.
  triangle('Triangle'),

  /// One anchor at each corner of the playing area.
  square('Square'),

  /// The square plus a fifth anchor at the middle of one touchline — a
  /// triangle sitting on the square's edge.
  squarePlusApex('Square + apex'),

  /// The square plus an anchor at the middle of each touchline.
  ring('Ring');

  const ReceiverLayoutShape(this.displayName);

  final String displayName;

  /// The shape used for [count] receivers.
  static ReceiverLayoutShape forCount(int count) => switch (count) {
        <= 3 => triangle,
        4 => square,
        5 => squarePlusApex,
        _ => ring,
      };
}

/// Perimeter positions, clockwise from the top-left corner, for [count]
/// receivers around a [court] with [margin] metres of clearance.
///
/// Returned as plain coordinates so the shapes can be reasoned about and
/// tested without constructing receivers.
List<({double x, double y})> receiverLayoutPositions(
  Court court, {
  required int count,
  required double margin,
}) {
  final w = court.widthMeters;
  final h = court.heightMeters;

  final topLeft = (x: -margin, y: -margin);
  final topMid = (x: w / 2, y: -margin);
  final topRight = (x: w + margin, y: -margin);
  final bottomRight = (x: w + margin, y: h + margin);
  final bottomMid = (x: w / 2, y: h + margin);
  final bottomLeft = (x: -margin, y: h + margin);

  return switch (ReceiverLayoutShape.forCount(count)) {
    // Three anchors cannot enclose a 40x20 rectangle from just outside it —
    // an enclosing triangle would have to stand tens of metres beyond the
    // hall's walls. The corners furthest from the apex therefore sit outside
    // the anchor triangle and position worst; this arrangement simply makes
    // that region as small as the geometry allows.
    ReceiverLayoutShape.triangle => [topLeft, topRight, bottomMid],
    ReceiverLayoutShape.square => [topLeft, topRight, bottomRight, bottomLeft],
    ReceiverLayoutShape.squarePlusApex => [
        topLeft,
        topMid,
        topRight,
        bottomRight,
        bottomLeft,
      ],
    ReceiverLayoutShape.ring => [
        topLeft,
        topMid,
        topRight,
        bottomRight,
        bottomMid,
        bottomLeft,
      ],
  };
}

/// Default anchor layout for [count] receivers ringing the playing area.
///
/// Real UWB anchors are mounted just outside the court and above head height,
/// so every preset places them off the floor of play at [mountHeight].
List<Receiver> defaultReceiverLayout(
  Court court, {
  int count = maxReceiverCount,
  double margin = AppSettings.defaultReceiverMarginMeters,
  double mountHeight = AppSettings.defaultMountHeightMeters,
}) {
  final clamped = count.clamp(minReceiverCount, maxReceiverCount);
  final positions =
      receiverLayoutPositions(court, count: clamped, margin: margin);

  return [
    for (var i = 0; i < positions.length; i++)
      Receiver(
        id: 'rx-${i + 1}',
        name: 'RX-${(i + 1).toString().padLeft(2, '0')}',
        x: positions[i].x,
        y: positions[i].y,
        z: mountHeight,
      ),
  ];
}

/// A receiver paired with its distance from the selected one.
@immutable
class ReceiverDistance {
  final Receiver receiver;

  /// Straight-line 3D distance in metres.
  final double distanceMeters;

  const ReceiverDistance(this.receiver, this.distanceMeters);
}

/// Everything the setup screen renders from.
@immutable
class SetupState {
  final Court court;
  final List<Receiver> receivers;
  final String? selectedReceiverId;
  final bool showGrid;

  const SetupState({
    required this.court,
    required this.receivers,
    this.selectedReceiverId,
    this.showGrid = false,
  });

  int get receiverCount => receivers.length;

  /// The preset shape the current receiver count corresponds to.
  ///
  /// Derived from the count rather than stored: after a receiver is dragged
  /// the arrangement is no longer the preset, and a stored shape would then
  /// be a claim the positions no longer support.
  ReceiverLayoutShape get layoutShape =>
      ReceiverLayoutShape.forCount(receivers.length);

  Receiver? get selectedReceiver {
    if (selectedReceiverId == null) return null;
    for (final r in receivers) {
      if (r.id == selectedReceiverId) return r;
    }
    return null;
  }

  /// Distances from the selected receiver to every other one, nearest first.
  ///
  /// Derived on demand rather than stored, so a drag or a numeric edit can
  /// never leave a stale distance behind.
  List<ReceiverDistance> get distancesFromSelection {
    final origin = selectedReceiver;
    if (origin == null) return const [];

    final result = [
      for (final r in receivers)
        if (r.id != origin.id) ReceiverDistance(r, origin.distanceTo(r)),
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return result;
  }

  SetupState copyWith({
    Court? court,
    List<Receiver>? receivers,
    String? selectedReceiverId,
    bool clearSelection = false,
    bool? showGrid,
  }) =>
      SetupState(
        court: court ?? this.court,
        receivers: receivers ?? this.receivers,
        selectedReceiverId: clearSelection
            ? null
            : (selectedReceiverId ?? this.selectedReceiverId),
        showGrid: showGrid ?? this.showGrid,
      );
}

/// Owns receiver placement and selection for the setup screen.
///
/// Deliberately free of widget imports: all input arrives as world metres, so
/// the same logic is testable without pumping a widget tree and reusable if
/// setup later moves to a wizard layout on phones.
class SetupController extends Notifier<SetupState> {
  /// World-space offset between the pointer and the dragged receiver's
  /// origin, captured at drag start so the marker does not jump under the
  /// cursor.
  Offset _grabOffset = Offset.zero;

  @override
  SetupState build() {
    final court = Court.handball();
    return SetupState(
      court: court,
      receivers: _layoutFor(court, maxReceiverCount),
    );
  }

  /// Builds a preset layout using the current settings.
  ///
  /// `ref.read`, not `ref.watch`: changing the default mount height must not
  /// silently reposition anchors the operator has already placed. It applies
  /// to the next layout generated — a count change or a reset.
  List<Receiver> _layoutFor(Court court, int count) {
    final settings = ref.read(appSettingsProvider);
    return defaultReceiverLayout(
      court,
      count: count,
      margin: settings.receiverMarginMeters,
      mountHeight: settings.receiverMountHeightMeters,
    );
  }

  /// Sets how many receivers the cell has, between [minReceiverCount] and
  /// [maxReceiverCount].
  ///
  /// Changing the count re-applies the preset for the new count rather than
  /// adding or dropping anchors at the end of the list. The presets are whole
  /// shapes: four corners are not a triangle plus one, and appending a fifth
  /// anchor to a triangle would leave a layout that is neither shape. The UI
  /// says so next to the control.
  void setReceiverCount(int count) {
    final clamped = count.clamp(minReceiverCount, maxReceiverCount);
    if (clamped == state.receivers.length) return;

    state = state.copyWith(
      receivers: _layoutFor(state.court, clamped),
      clearSelection: true,
    );
  }

  void setShowGrid(bool value) => state = state.copyWith(showGrid: value);

  void select(String? receiverId) => state = receiverId == null
      ? state.copyWith(clearSelection: true)
      : state.copyWith(selectedReceiverId: receiverId);

  /// Returns the receiver whose marker contains [worldPosition], or null.
  ///
  /// [toleranceMeters] should be derived from the on-screen marker size so
  /// that the target stays a constant number of pixels at any zoom.
  Receiver? receiverAt(Offset worldPosition, double toleranceMeters) {
    Receiver? best;
    var bestDistance = double.infinity;

    for (final r in state.receivers) {
      final d = (Offset(r.x, r.y) - worldPosition).distance;
      if (d <= toleranceMeters && d < bestDistance) {
        best = r;
        bestDistance = d;
      }
    }
    return best;
  }

  /// Selects the receiver under the pointer, or clears the selection.
  /// Returns true if something was hit.
  bool selectAt(Offset worldPosition, double toleranceMeters) {
    final hit = receiverAt(worldPosition, toleranceMeters);
    select(hit?.id);
    return hit != null;
  }

  /// Begins dragging whatever lies under the pointer.
  ///
  /// [pointerDown] must be where the pointer actually landed, not where the
  /// pan gesture was recognised — see [CourtDragStartCallback]. Anchoring the
  /// grab offset here keeps the receiver locked to the cursor for the rest of
  /// the gesture instead of trailing it by the touch slop.
  bool beginDrag(Offset pointerDown, double toleranceMeters) {
    final hit = receiverAt(pointerDown, toleranceMeters);
    if (hit == null) {
      select(null);
      return false;
    }
    _grabOffset = Offset(hit.x, hit.y) - pointerDown;
    select(hit.id);
    return true;
  }

  /// Moves the dragged receiver to follow the pointer.
  void updateDrag(Offset worldPosition) {
    final selected = state.selectedReceiver;
    if (selected == null) return;

    final target = worldPosition + _grabOffset;
    moveReceiver(selected.id, x: target.dx, y: target.dy);
  }

  void endDrag() => _grabOffset = Offset.zero;

  /// Sets any subset of a receiver's coordinates, in metres.
  ///
  /// This is the single mutation point for position, shared by dragging and
  /// by the inspector's numeric fields, so the two can never diverge.
  void moveReceiver(String id, {double? x, double? y, double? z}) {
    state = state.copyWith(
      receivers: [
        for (final r in state.receivers)
          if (r.id == id) r.copyWith(x: x, y: y, z: z) else r,
      ],
    );
  }

  /// Restores the preset layout for the current receiver count.
  void resetLayout() => state = state.copyWith(
        receivers: _layoutFor(state.court, state.receivers.length),
        clearSelection: true,
      );

  /// Clamps a world point to the region the canvas can display, so a receiver
  /// cannot be dragged out of sight.
  static Offset clampToVisibleWorld(Offset world, Rect visibleWorld) => Offset(
        world.dx.clamp(visibleWorld.left, visibleWorld.right),
        world.dy.clamp(visibleWorld.top, visibleWorld.bottom),
      );

  /// Largest 3D distance between any two receivers, in metres.
  ///
  /// A quick sanity signal for anchor spread: a UWB cell with very short
  /// baselines positions poorly.
  double get maxBaseline {
    var best = 0.0;
    final rs = state.receivers;
    for (var i = 0; i < rs.length; i++) {
      for (var j = i + 1; j < rs.length; j++) {
        best = math.max(best, rs[i].distanceTo(rs[j]));
      }
    }
    return best;
  }
}

final setupControllerProvider =
    NotifierProvider<SetupController, SetupState>(SetupController.new);
