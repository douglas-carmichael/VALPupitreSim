<p align="center">
  <img src="VALPupitreSim/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" height="128" alt="VALPupitreSim icon">
</p>

<h1 align="center">VALPupitreSim</h1>

<p align="center">
  A macOS simulator of the manual-driving cab (<i>pupitre de conduite manuelle</i>) of a <b>VAL 206</b> automated metro trainset.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2026.5%2B-lightgrey">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-orange">
  <img alt="UI" src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20RealityKit-blue">
</p>

---

## Overview

The **VAL** (*Véhicule Automatique Léger*) is the rubber-tired automated metro
built by Matra Transport for Lille, in revenue service since 1983. The **VAL 206**
takes its name from its 2.06 m body width.

VALPupitreSim puts you at the VAL 206 control desk on a 1.5 km test track with
three stations. You can drive the train yourself in manual mode (PM) or let the
automatic pilot (PA) run it between stations. You can also plug in a USB
hardware pupitre and drive with that.

## Features

- **Traction and braking physics.** A single master controller (T/F lever)
  handles traction, coasting and service braking. A latched emergency brake
  sits alongside it.
- **PA / PM driving modes.**
  - In PA, a closed-loop constant-deceleration profile berths the train within
    about ±2 cm of the platform mark.
  - PA runs the dwell and departure at each station automatically.
  - **NAV** shuttle mode turns the train back at each terminus on its own.
- **KACOP dead-man vigilance.** The device detects the rising edge of each
  press. It warns you after 14 s without an acknowledgment and applies the
  emergency brake at 20 s.
- **Authentic interlocks:**
  - Traction is cut when KG is off, the reverser is in neutral, the emergency
    brake is latched, or a door is open.
  - Doors only open at a station, with the train stopped and KG on.
  - Service braking isn't subject to the traction interlocks.
- **Real cab nomenclature.** The desk has the KG, KIBS (not yet simulated),
  KPH, PA and NAV switches, the AV/0/AR reverser, PO G / PO D / FP door buttons, and the TRAC,
  FREIN, HM, PM, PA, PORT and URG voyants.
- **Procedural audio.** Every sound is synthesized live by a single
  `AVAudioSourceNode`, with no samples on disk. That covers the motor whine,
  brake hiss, horn, compressor, vigilance buzzer and door chime.
- **RealityKit 3D views.** There's a chase camera, a top-down track overview,
  and a separate from-the-cab window (**VUE CABINE**).
- **USB HID input.** Any HID joystick or gamepad works, including the
  Raspberry Pi Pico-based 12-button + 1-axis pupitre. Without hardware, you can
  drive everything with the mouse.
- **Built-in operator's guide** (in French) inside the app.

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 26.5 or later |
| Xcode | A version that includes the macOS 26.5 SDK |
| Hardware (optional) | A USB HID gamepad/joystick, or the Pico-based pupitre |

## Getting Started

### Build and run in Xcode

```sh
git clone https://github.com/douglas-carmichael/VALPupitreSim.git
cd VALPupitreSim
open VALPupitreSim.xcodeproj
```

Select the **VALPupitreSim** scheme and press **⌘R**.

### Build from the command line

```sh
xcodebuild -project VALPupitreSim.xcodeproj \
           -scheme VALPupitreSim \
           -configuration Debug build
```

Xcode creates the scheme automatically the first time you open the project.
If `xcodebuild` reports a missing scheme, open the project in Xcode once and
try again.

## Quick Start

1. Turn **KG** on. You'll hear the compressor hum start.
2. Move the **reverser** to **AV** (forward) or **AR** (reverse).
3. Pick a mode:
   - **Automatic:** flip **PA** on. The train drives to the next station, holds
     there for a 10 s dwell, and moves on. Turn **NAV** on as well to shuttle
     end-to-end indefinitely.
   - **Manual:** leave PA off and drag the master controller up toward
     **TRAC**. Tap **KACOP** at least every 14 s.
4. At a station, stop the train and wait for **DOORS OK** to light. Then use
   **PO G** / **PO D** to open the doors and **FP** to close them.
5. Strike **ARRÊT** for an emergency stop, and press it again to release.

The full procedures are in [`OPERATOR_GUIDE.md`](OPERATOR_GUIDE.md).

## Test Track

| Marker | Station | Position |
|--------|---------|----------|
| P25 | QUATRE-CANTONS | 250 m |
| P75 | RÉPUBLIQUE | 750 m |
| P125 | GRAND-PLACE | 1 250 m |

## USB HID Mapping

| HID input | Function |
|-----------|----------|
| Button 1 | KG |
| Button 2 | KACOP |
| Button 3 | KIBS |
| Button 4 | KPH |
| Button 5 | Horn (AVA) |
| Button 6 | PO G (open left doors) |
| Button 7 | PO D (open right doors) |
| Button 8 | FP (close doors) |
| Button 9 | Reverser AV |
| Button 10 | Reverser 0 |
| Button 11 | Reverser AR |
| Button 12 | Emergency brake (toggle) |
| Y axis | Master controller (stick forward = traction) |

Buttons 1, 3 and 4 follow the button level (on while held), so wire them to
latching switches. When a device is connected, its name shows in the HUD
next to `PUPITRE USB:`. NAV has no HID button and is set on screen only.

## Architecture

The whole app is **one observable model driven by one frame loop**:

```
HID device ─┐                          ┌─→ Train3DView        (RealityKit chase cam)
mouse/touch ─┼─→ SimulationModel ──────┼─→ TrackOverview3DView (RealityKit top-down map)
            (inputs)   │  update(dt:)   ├─→ PupitreView        (on-screen controls + voyants)
                       │                └─→ AudioEngine        (procedural synth)
                       └── single @Observable source of truth ──
```

| File | Role |
|------|------|
| `SimulationModel.swift` | The single source of truth. Holds all train state, switch state, voyant logic, physics constants and the PA profile. |
| `ContentView.swift` | Root view. Owns the model, audio and HID managers, runs the ~60 Hz physics loop, and lays out the HUD. |
| `PupitreView.swift` | The on-screen control desk: switches, reverser, master controller, voyants, KACOP and emergency brake. |
| `AudioEngine.swift` | A single `AVAudioSourceNode` that synthesizes every voice. Its render path does no allocation and takes no locks. |
| `HIDInputManager.swift` | `IOHIDManager` USB input feeding the model. |
| `Train3DView.swift` | RealityKit chase-camera view. |
| `TrackOverview3DView.swift` | RealityKit orthographic map of the line. |
| `Cab3DView.swift` | RealityKit from-the-cab view, shown in its own window. |
| `RealityKitSupport.swift` | Shared entity, material and light builders. |
| `OperatorGuideView.swift` | The in-app operator's guide (French). |

## Documentation

- [`OPERATOR_GUIDE.md`](OPERATOR_GUIDE.md) is the theory of operation and
  operator's guide, and the authoritative reference for the domain model.
- [`CLAUDE.md`](CLAUDE.md) holds architecture notes and conventions for
  contributors.

## Contributing

Issues and pull requests are welcome. If you change simulated behavior
(constants, the PA profile, interlocks, audio or HID mapping), update **all
three** of these together:

1. `SimulationModel.swift`
2. `OPERATOR_GUIDE.md` (English)
3. `OperatorGuideView.swift` (French, in-app)

New state should use the real VAL cab labels listed in the guide's glossary.

## Acknowledgments

The switch nomenclature and desk layout follow the electronics build-log video
that inspired the project. VAL is a system originally developed by Matra
Transport. This is an independent hobby project and isn't affiliated with or
endorsed by the system's manufacturers or operators.

## License

No license has been specified yet. All rights reserved by the author until a
license is added.
