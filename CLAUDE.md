# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**VALPupitreSim** is a macOS SwiftUI app that simulates the manual-driving cab
(*pupitre de conduite manuelle*) of a **VAL 206** rubber-tired automated metro
trainset, on a 1.5 km test track with three stations. It models traction/braking
physics, the PA (automatic) / PM (manual) driving modes, the KACOP dead-man
vigilance device, station door interlocks, procedurally-synthesized audio, and a
RealityKit 3D visualization. A USB HID pupitre (a Raspberry Pi Pico presenting as a
12-button + 1-axis gamepad) can drive it; mouse input on the on-screen controls
works with no hardware. A **PCC link** advertises the cab over Bonjour so a PCC
(the sibling `../metroSystem` dispatcher, or any client) can monitor it and —
when the cab's COMMANDE selector is on PCC — drive it over the network, move
the rame onto the PCC's own line (typically a loop), impose a stopping point,
and report the line's other rames for the 3D views to show; `PCC_API.md`
specifies the protocol.

`OPERATOR_GUIDE.md` is the authoritative theory-of-operation reference and the
single best source for the domain model (modes, switches, interlocks, audio,
HID mapping). Read it before changing simulation behavior.

## Build & run

- **App target / scheme:** `VALPupitreSim` (single target, no test target, no linter configured).
- **Platform:** macOS only. Deployment target macOS 26.5, Swift 5.0, hardened runtime on.
- **Build:** `xcodebuild -project VALPupitreSim.xcodeproj -scheme VALPupitreSim -configuration Debug build`
- **Run:** open `VALPupitreSim.xcodeproj` in Xcode and ⌘R (the app needs a window + audio + HID run loop; it isn't a CLI).
- Schemes live in per-user `xcuserdata` (gitignored); Xcode regenerates the `VALPupitreSim` scheme automatically on open.

## Architecture

The whole app is **one observable model driven by one frame loop**. Understand
these two facts and the rest follows:

1. **`SimulationModel` (`SimulationModel.swift`) is the single source of truth.**
   An `@Observable` class holding all train state, switch/button state, voyant
   (indicator) logic, and physics constants. *Every* other component either
   writes inputs into it or reads state out of it — there is no other shared
   state. Speeds are stored in m/s internally; km/h is presentation-only.

2. **`ContentView.runPhysicsLoop()` is the heartbeat.** A `.task` async loop
   ticks ~every 16 ms and calls `model.update(dt:)`, then `audio.update(model:)`,
   then `pcc?.tick()` (dt clamped to ≤ 0.1 s). `model.update(dt:)` is the entire
   simulation step: it consumes remote presses, runs the PCC link watchdog,
   resolves the effective controller value, integrates speed/position,
   computes voyants, animates doors, and runs the dead-man timer.
   `PCCLink.tick()` then drops a silent controller, emits events and streams
   state to the connected PCCs.

Data flow each frame:

```
HID device ───┐                          ┌─→ Train3DView         (RealityKit chase cam)
mouse/touch ──┼─→ SimulationModel ───────┼─→ TrackOverview3DView (RealityKit top-down map)
PCC commands ─┘   update(dt:)            ├─→ PupitreView         (on-screen controls + voyants)
  (PCCLink)       single @Observable     ├─→ AudioEngine         (procedural synth)
                  source of truth        └─→ PCCLink             (state + events to PCCs)
```

The RealityKit views read the per-frame model values in `body`, so Observation
invalidates them when the model changes and `RealityView` re-runs its `update`
closure; they don't run their own clocks for simulation.

### Components

- **`ContentView.swift`** — root view. Owns the `SimulationModel`, `AudioEngine`,
  `HIDInputManager` and `PCCLink`; runs the physics loop; lays out the HUD
  (status bar with the COMMANDE selector, station bar with the PCC pill, the
  POINT D'ARRÊT distance and the emergency-brake cause), the two 3D views, and
  the pupitre. Wires
  `model.onDoorChime` to the audio engine and starts HID and the PCC link in
  `.onAppear`.
- **`PupitreView.swift`** — the virtual control desk. All on-screen switches,
  the reverser, the master controller (vertical drag slider with detents),
  voyants, push buttons, KACOP/veille button, speedometer, and emergency brake.
  Controls bind directly to `SimulationModel` via `@Bindable`.
- **`AudioEngine.swift`** — procedural audio. A *single* `AVAudioSourceNode`
  synthesizes every voice (motor, brake hiss, horn, compressor, vigilance
  buzzer, door chime) — no audio samples on disk. `update(model:)` snapshots
  model state into live parameters once per frame.
- **`HIDInputManager.swift`** — `IOHIDManager`-based USB input → model
  (macOS-only; there is a non-macOS stub so the file still compiles elsewhere).
- **`PCCLink.swift`** — the PCC link server (Network.framework): Bonjour
  advertisement of `_valpupitre._tcp` (port 5206, falling back to any free
  port), sessions, the single control token, command dispatch into the model,
  the event diff and the rate-limited state stream. Persists the cab's
  identity, rame number and COMMANDE position in `UserDefaults` (`pcc*` keys,
  overridable as launch arguments).
- **`PCCProtocol.swift`** — the PCC link wire types. **`PCC_API.md`** is the
  specification; change them together.
- **`PCCLinkPanel.swift`** — the HUD popover with the link's details and the
  rame-number field.
- **`RameTelemetry.swift`** — the rame's instruments (traction chain bench
  quantities, auxiliaries), advanced by `update(dt:)` into `model.telemetry`
  and streamed as `state.telemetry`. Its VAL 206 constants match metroSystem's
  `Sim` (traction chain) — keep them in step.
- **`Train3DView.swift`** — RealityKit chase-cam view of the train on the guideway.
- **`TrackOverview3DView.swift`** — RealityKit orthographic top-down map of the
  whole line with a moving rame marker (the test track to scale, a PCC's loop
  as a racetrack) and markers for the other rames.
- **`Cab3DView.swift`** — RealityKit from-the-cab view (own window) with a
  SwiftUI HUD overlay.
- **`TrackGeometry.swift`** — `SceneTrack` (distance along the line → a
  `TrackFrame` in the scene): `StraightSceneTrack`, `CircleSceneTrack` (loops,
  in the chase and cab views) and `RacetrackSceneTrack` (loops, on the map),
  plus `RK.sweptBar`, which builds guideway, curbs and platforms as meshes
  swept along a track.
- **`OtherRamesLayer.swift`** — the other rames a PCC reports
  (`model.otherRames`), pooled and placed on the track in the chase and cab
  views.
- **`RealityKitSupport.swift`** — shared entity/material/light builders (`RK`)
  and the `PColor` typealias.
- **`OperatorGuideView.swift`** — in-app guide sheet (French).

## Conventions & gotchas

- **Naming follows real VAL cab labels**, not generic terms: `kg` (Coupure
  Générale / master power), `kacop` (dead-man ack), `kibs`, `kph` (headlights),
  `paMode`, reverser `direction` (AV/0/AR). `OPERATOR_GUIDE.md` §2 is the
  glossary — match it when adding state.

- **Momentary buttons are level booleans; the model detects rising edges.**
  KACOP and the door buttons (`doorOpenLeft/Right`, `doorClose`) are held-true
  while pressed. `update(dt:)` compares against `previous*` ivars (all
  `@ObservationIgnored`) to act only on the press transition. A wedged-down
  button must not satisfy a requirement — preserve this when touching input
  handling. The `@ObservationIgnored` markers also matter: edge-tracking and
  door-target state are deliberately excluded from observation to avoid
  spurious view invalidation.

- **PA mode replaces the driver's input.** When `paActive`, `update(dt:)` uses
  `computePAController()` and ignores `masterController` entirely. PA also
  **bypasses the dead-man device** by design — the deadman timer only advances
  under manual control (`!paActive`).

- **Interlocks are asymmetric and load-bearing:** traction is inhibited when KG
  is off, the reverser is neutral, the emergency brake is latched, or any door
  is > 2% open — but **service braking is outside that gate** (it works with
  doors open, in neutral, etc.). With KG off, though, no braking acts at all;
  the train only drifts down on residual resistance. Doors only operate
  when stopped (< 0.1 m/s) at a station with KG on. Don't "simplify" these into
  a single gate.

- **The two docs must move together.** `OperatorGuideView.swift` (French, in-app)
  mirrors `OPERATOR_GUIDE.md` (English, repo root). Both files say so. Any change
  to simulated behavior (constants, PA profile, interlocks, audio, HID mapping,
  PCC link) should update all three: the model, the Markdown guide, and the
  in-app view. A change to the PCC wire format also updates `PCC_API.md`.

- **The COMMANDE authority gates every local input path.** Under
  `model.authority == .pcc`, `PupitreView` stops hit-testing every control but
  ARRÊT and `HIDInputManager` ignores everything but button 12. A new input
  path must honour the same gate. Entering PCC command releases the momentary
  buttons (`kacop`, `hornPressed`, the door buttons), because a HID release
  would no longer get through. Only the cab moves the selector; the PCC can't.

- **Remote presses are one-shot edges, never levels.** The PCC's KACOP and
  door buttons go through `pressKacop()` / `pressDoorOpen(left:right:)` /
  `pressDoorClose()`: pending flags that `update(dt:)` ORs into the rising
  edges and clears. They never touch `kacop` / `doorOpenLeft` / …, so a remote
  press can't look like a wedged button.

- **The PCC link watchdog is simulation behavior, so it lives in the model.**
  `update(dt:)` advances `pccLinkSilence` under PCC command and latches the
  emergency brake past `pccLinkTimeout`; `PCCLink` only calls `pccHeartbeat()`
  for each line from the controlling session. Latch the brake from code with
  `applyEmergencyBrake(_:)` so `emergencyBrakeCause` is right; a plain set (the
  ARRÊT binding, HID button 12) counts as `.cab`.

- **Networking runs on the main queue.** `NWListener` / `NWConnection` deliver
  their callbacks on `.main` and hop in with `MainActor.assumeIsolated`, so
  sessions and the model are touched in arrival order on the main actor. With
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, wire types are declared
  `nonisolated` — otherwise their `Codable` conformances are main-actor-isolated
  and warn when used with `JSONEncoder`/`JSONDecoder`. `NWConnection.cancel()`
  discards queued sends: close a session that is owed a reply with
  `close(_:flushing: true)`.

- **Sandbox and Local Network privacy.** The app is sandboxed; listening needs
  `ENABLE_INCOMING_NETWORK_CONNECTIONS` (the `network.server` entitlement).
  `VALPupitreSim/Info.plist` holds only `NSBonjourServices`; Xcode merges it
  into the generated plist (`INFOPLIST_FILE`), and a membership exception keeps
  it out of the bundle's resources. macOS holds the Bonjour advertisement as
  *pending* until the user allows local network access: the cab stays
  reachable by address but isn't discoverable until then. (zsh shadows
  `/usr/bin/log` with a builtin; call it by full path when reading the
  `mDNSResponder` log.)

- **The line is model state.** `model.layout` (`TrackLayout`) is the test track
  or a PCC's line; `joinLine(_:at:)` moves the rame onto a PCC's line, and the
  authority going back to `.local` returns it to `testTrackPosition` and lifts
  the PCC's stopping point and traffic. On a loop every position goes through
  `onLine(_:)` (wraps round), and `aheadDistance(toPosition:)` counts
  everything as ahead except the last `loopBehindWindow` metres — use it, not
  a bare subtraction, for anything measured along the line.

- **Positions are of car 1's centre**, the car at the AV end: the rame reaches
  `SimulationModel.avEndM` (6.4 m) ahead of `positionM` and `arEndM` (19.6 m)
  behind, whichever way it runs. Stations, the PCC's `stopLimitM` and the
  other rames' positions use the same reference, and the 3D views place car 2
  `carPitchM` behind car 1. `hello.geometry` tells PCCs.

- **The other rames are display only.** `otherRames` is what the controlling
  PCC last reported (`setTraffic`), carried forward at each rame's speed in
  `update(dt:)` and dropped after `trafficTimeout`; `PCCLink` clears it
  whenever control changes hands, and `relocate` / LOCALE clear it too.
  Nothing in the physics reacts to it — the PCC's stopping point is what
  keeps the rame clear. `trafficNeighbours` gives the nearest one ahead and
  behind with the clear gap, for `TrafficReadout` (chase view, cab HUD);
  `OtherRamesLayer` puts a distance-scaled beacon on rames past 60 m.

- **Telemetry is derived, never fed back.** `RameTelemetry.advance` takes the
  step's regime and commanded acceleration; nothing in the physics reads it,
  and it is `@ObservationIgnored` (no view shows it).

- **The PCC link can be exercised without the GUI.** `SimulationModel.swift`,
  `RameTelemetry.swift`, `PCCProtocol.swift` and `PCCLink.swift` have no UI
  dependencies: compile them
  with `swiftc -swift-version 5 -default-isolation MainActor` and a few-line
  `main.swift` that ticks `model.update(dt:)` and `link.tick()` on a 60 Hz
  `Timer`, and you have a headless cab to drive with `nc` or a script. Pass it
  a `UserDefaults(suiteName:)` so it doesn't touch the app's settings.

- **Audio runs on the render thread.** Live parameters are written from the main
  thread and read by the `AVAudioSourceNode` callback. Keep the render path
  allocation- and lock-free — note the custom xorshift `nextNoise()` exists
  specifically to avoid the locking RNG in `Float.random`.

- **RealityKit views cache entities in a rig** (`TrainSceneRig` /
  `OverviewSceneRig` / `CabSceneRig`, held in `@State`), built once in the
  `RealityView` make closure and mutated per frame in `apply(...)` rather than
  rebuilding the scene. Add new animated elements by stashing the entity on the
  rig at build time and updating it there (or, for a varying number of them,
  in a pool that grows and hides, like `OtherRamesLayer`). Only swap
  materials/components when a value changes (see the headlight handling).
  Each `RealityView` carries `.id(layout.id)`, so a change of line rebuilds its
  scene, and everything is placed through the rig's `SceneTrack`. RealityKit
  has no fog, and its orthographic `scale` is a half-extent like SceneKit's
  `orthographicScale`. To look at a scene without running the app, compile
  the rig's file (with `private` dropped from the rig class) together with
  `SimulationModel.swift`, `TrackGeometry.swift`, `RealityKitSupport.swift`
  and `OtherRamesLayer.swift`, and render it offscreen with
  `RealityRenderer` into an `MTLTexture`.

- **Cross-platform shims exist despite macOS-only shipping:** `PColor`
  (NSColor/UIColor typealias) and the `#if os(macOS)` HID stub. Keep new
  platform-specific code behind the same guards so the file set keeps compiling.
