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
works with no hardware.

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
   ticks ~every 16 ms and calls `model.update(dt:)` then `audio.update(model:)`
   (dt clamped to ≤ 0.1 s). `model.update(dt:)` is the entire simulation step:
   it resolves the effective controller value, integrates speed/position,
   computes voyants, animates doors, and runs the dead-man timer.

Data flow each frame:

```
HID device ─┐                          ┌─→ Train3DView      (RealityKit chase cam)
mouse/touch ─┼─→ SimulationModel ──────┼─→ TrackOverview3DView (RealityKit top-down map)
            (inputs)   │  update(dt:)   ├─→ PupitreView      (on-screen controls + voyants)
                       │                └─→ AudioEngine      (procedural synth)
                       └── single @Observable source of truth ──
```

The RealityKit views read the per-frame model values in `body`, so Observation
invalidates them when the model changes and `RealityView` re-runs its `update`
closure; they don't run their own clocks for simulation.

### Components

- **`ContentView.swift`** — root view. Owns the `SimulationModel`, `AudioEngine`,
  and `HIDInputManager`; runs the physics loop; lays out the HUD (status bar,
  station bar), the two 3D views, and the pupitre. Wires `model.onDoorChime` to
  the audio engine in `.onAppear`.
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
- **`Train3DView.swift`** — RealityKit chase-cam view of the train on the guideway.
- **`TrackOverview3DView.swift`** — RealityKit orthographic top-down map of the
  whole line with a moving rame marker.
- **`Cab3DView.swift`** — RealityKit from-the-cab view (own window) with a
  SwiftUI HUD overlay.
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
  to simulated behavior (constants, PA profile, interlocks, audio, HID mapping)
  should update all three: the model, the Markdown guide, and the in-app view.

- **Audio runs on the render thread.** Live parameters are written from the main
  thread and read by the `AVAudioSourceNode` callback. Keep the render path
  allocation- and lock-free — note the custom xorshift `nextNoise()` exists
  specifically to avoid the locking RNG in `Float.random`.

- **RealityKit views cache entities in a rig** (`TrainSceneRig` /
  `OverviewSceneRig` / `CabSceneRig`, held in `@State`), built once in the
  `RealityView` make closure and mutated per frame in `apply(...)` rather than
  rebuilding the scene. Add new animated elements by stashing the entity on the
  rig at build time and updating it there. Only swap materials/components when
  a value changes (see the headlight handling). RealityKit has no fog, and its
  orthographic `scale` is a half-extent like SceneKit's `orthographicScale`.

- **Cross-platform shims exist despite macOS-only shipping:** `PColor`
  (NSColor/UIColor typealias) and the `#if os(macOS)` HID stub. Keep new
  platform-specific code behind the same guards so the file set keeps compiling.
