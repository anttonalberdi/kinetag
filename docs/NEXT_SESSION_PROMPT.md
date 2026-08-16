# Kinetag — continuation prompt (Phases 5–9)

Paste everything below the line into a new session started in
`/Users/anttonalberdi/Github/kinetag`.

---

You are the lead software engineer on **Kinetag**, a cross-platform indoor
sports tracking application (Flutter/Dart). The eventual system is UWB player
tags + receivers/anchors + a hub, with the app doing setup, recording, replay
and analysis. The first sport is handball. I develop on a **Mac in VS Code**;
macOS desktop is the first target.

Read `CLAUDE.md` if present, then `git log` and the `lib/` tree to orient
yourself before writing code.

## Current state — Phases 1–4 are complete and committed

Three commits exist: initial, `Kinetag foundation`, `Phase 4: receiver setup`.
**91 tests pass, `flutter analyze` is clean, and `flutter build macos`
succeeds.** The app runs with `flutter run -d macos`.

Environment already set up and verified: Flutter 3.47.0 / Dart 3.13.0,
Xcode 26.1.1 (selected), CocoaPods 1.17.0. Dependencies:
`flutter_riverpod ^3.4.2`, `meta`, `uuid`, `cupertino_icons`.

### What exists

```
lib/src/core/court_view_transform.dart     world metres <-> screen pixels
lib/src/domain/                            Court, Receiver, Tag, Player,
                                           TagAssignment, PositionSample,
                                           PositionFrame, Session, + barrel
lib/src/features/court/                    CourtCanvas, CourtLayer,
                                           HandballCourtGeometry/Layer,
                                           CourtTheme, MetreGridLayer
lib/src/features/setup/                    SetupController + state, receiver
                                           layer, inspector, coordinate field
lib/src/features/home/home_screen.dart
lib/src/app/                               KinetagApp, AppShell (nav)
lib/src/tracking/tracking_message.dart     sealed TrackingMessage hierarchy
```

Working today: 40x20 m handball court at true metre scale with regulation
markings; six receivers around the perimeter; click to select; drag to move;
numeric X/Y/Z editing; live inter-receiver distances; 1 m debug grid;
adaptive navigation (rail on wide windows, bottom bar on narrow).

### Decisions already made — follow these, do not relitigate

1. **Riverpod** is the single state-management framework. `ProviderScope` in
   `main.dart` is the injection point for swapping simulator -> hardware ->
   recording. Do not introduce a second framework.
2. **Timestamps are `int` microseconds since epoch**, never float seconds. At
   50–100 Hz, float seconds lose sub-millisecond precision and that error
   surfaces directly as noise in derived velocity.
3. **World +Y points down**, matching Flutter's screen convention, so there is
   no axis flip anywhere. Real hardware output must be adapted to this at the
   tracking-source boundary.
4. **Screen pixels never enter domain logic.** `CourtCanvas` pointer callbacks
   report world metres plus the `CourtViewTransform`, so callers can convert a
   pixel-sized hit tolerance to metres themselves.
5. **`Session` stores its setup by value** (court, receivers, tags, players,
   assignments). Moving a receiver later must never alter a historical
   recording. There is a test asserting this.
6. **Derived values are derived, not stored** — inter-receiver distances are
   computed on read. Apply the same rule to analytics.
7. `Session.positioningAlgorithmVersion` exists so sessions can later be
   reprocessed with improved positioning and the results told apart.
8. `TrackingMessage` carries a `sequenceNumber` from the start, for the future
   hub protocol's dropped-packet detection.
9. **Persistence will be SQLite** via `sqflite_common_ffi` on desktop and
   `sqflite` on mobile — chosen but **not yet installed or implemented**.
   Split metadata (`sessions`) from samples (`position_samples`, indexed on
   `session_id, timestamp_micros`); that index is what makes replay scrubbing
   cheap. Keep a schema slot reserved for raw UWB measurements. All of it goes
   behind a repository interface — no widget touches SQL.

### Two environment quirks that cost time last session

- **`screencapture` returns the wallpaper with all windows stripped**, because
  Screen Recording permission is denied to the terminal. Do not burn time
  trying to screenshot the running app. To verify visuals, render the widget
  tree to a PNG inside a widget test via `RepaintBoundary.toImage`, write it to
  the scratchpad, and read it back. Note that `flutter test` uses a placeholder
  font, so text renders as grey boxes — that is expected, not a bug.
- `Path.getBounds()` is float32 internally, so tolerances tighter than ~1e-6
  will flake on non-representable values like 0.15.

## What to build next

Work incrementally. Before each phase: state what you intend to implement and
which files change; implement it; run `flutter analyze` and `flutter test`;
verify the macOS build; summarise; then continue. Keep the app runnable after
every phase and commit each phase separately.

**Do not add a `Co-Authored-By` trailer to commits.**

### Phase 5 — tracking abstraction + simulator

`lib/src/tracking/tracking_message.dart` already defines the sealed
`TrackingMessage` hierarchy (`PositionFrameMessage`, `TrackingStatusMessage`,
`TrackingErrorMessage`, `SequenceGapMessage`) and `TrackingSourceStatus`.
**The `TrackingSource` interface itself is not written yet** — write it:

```dart
abstract class TrackingSource {
  Stream<TrackingMessage> get messages;
  TrackingSourceStatus get status;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> dispose();
}
```

Then implement `SimulatorTrackingSource` only. It must emit through this
interface so `KinetagHardwareTrackingSource` and
`RecordedSessionTrackingSource` can replace it later without touching the UI.

Defaults to use unless I say otherwise: **12 simulated players (two teams of
six) at 20 Hz**, with loose role-based movement rather than generic paths —
it costs little extra and makes team metrics (centroid, width, compactness)
meaningful later. Trajectories must be visibly different per player, smooth,
and constrained to the court. Expose the source via a Riverpod provider.

### Phase 6 — live view

Court + moving tags + labels, elapsed session time, tracking status, and
Start/Stop Recording controls. Reuse `CourtCanvas` with a new player layer;
do not build a second renderer. Keep per-frame computation off the render
path. Avoid dashboard clutter — the point is proving continuous position data
can be consumed and visualised.

### Phase 7 — storage

Add the SQLite dependencies and implement the repository described in
decision 9. Persist session metadata and position samples. Batch sample
writes; do not write one row per sample synchronously on the UI isolate.

### Phase 8 — session browser + replay

List recorded sessions, open one, and replay it with play/pause, a timeline
scrubber, current/elapsed time, and playback speed if straightforward.
Scrubbing must work backwards and forwards. Replay should feed the same
`PositionFrame` representation into the same canvas the live view uses —
ideally as a `RecordedSessionTrackingSource` behind the same abstraction.

### Phase 9 — basic analytics

Per-player total distance, instantaneous speed, max speed, average speed.
Derived from stored trajectories, never the sole source of truth. Advanced
metrics (acceleration, heatmaps, team centroid/width/area, tactical analysis)
are explicitly future work.

Completing Phases 5–9 reaches **Prototype 0.1**, the acceptance target. Do not
add cloud services, authentication, or real UWB integration before then.

## Standing constraints

- Keep UI, domain, tracking, storage and analytics separated.
- Immutable models; small focused classes; no giant widgets; no global mutable
  state; document non-obvious maths.
- Design for eventually ~30 tags at 50–100 samples/second/tag. Do not
  prematurely optimise, but do not make choices that would force a UI rewrite
  for high-rate data.
- Structure layouts so they can later adapt to phone/tablet/desktop; optimise
  now for a normal Mac laptop window, avoiding fixed pixel layouts.
- Add tests where they carry weight. Run `flutter analyze` and `flutter test`
  before calling a milestone done.
- Flag explicitly any decision that could affect hardware integration, data
  integrity, coordinate mathematics, or cross-platform compatibility.

Start with Phase 5.
