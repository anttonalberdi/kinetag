import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../domain/domain.dart';

/// Default anchor layout: six receivers ringing the playing area.
///
/// Real UWB anchors are mounted just outside the court and above head height.
/// Spacing them around the perimeter (rather than only at the corners) keeps
/// the geometric dilution of precision reasonable across the whole floor,
/// which is why the two mid-touchline anchors are included.
List<Receiver> defaultReceiverLayout(Court court) {
  final w = court.widthMeters;
  final h = court.heightMeters;
  const margin = 1.2; // metres outside the sideline
  const mountHeight = 2.4;

  return [
    Receiver(id: 'rx-1', name: 'RX-01', x: -margin, y: -margin, z: mountHeight),
    Receiver(id: 'rx-2', name: 'RX-02', x: w / 2, y: -margin, z: mountHeight),
    Receiver(
        id: 'rx-3', name: 'RX-03', x: w + margin, y: -margin, z: mountHeight),
    Receiver(
        id: 'rx-4', name: 'RX-04', x: w + margin, y: h + margin, z: mountHeight),
    Receiver(
        id: 'rx-5', name: 'RX-05', x: w / 2, y: h + margin, z: mountHeight),
    Receiver(
        id: 'rx-6', name: 'RX-06', x: -margin, y: h + margin, z: mountHeight),
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
    return SetupState(court: court, receivers: defaultReceiverLayout(court));
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

  /// Restores the default six-receiver ring.
  void resetLayout() => state = state.copyWith(
        receivers: defaultReceiverLayout(state.court),
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
