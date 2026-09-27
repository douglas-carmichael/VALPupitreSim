# VAL 206 — Guide d'Exploitation & Théorie de Fonctionnement

*Operator's Guide & Theory of Operation for the **VALPupitreSim** macOS application.*

This document is the source-of-truth reference for the in-app guide (see
`OperatorGuideView.swift`). Update both together.

---

## 1. Introduction

The **VAL** (*Véhicule Automatique Léger*) is a rubber-tired automated metro
system developed by **Matra Transport** for the Lille Métropole network and
placed in revenue service in 1983. The **VAL 206** variant takes its name
from the body width of its vehicles: **2.06 m**.

This simulator reproduces the **manual-driving cab** (*pupitre de conduite
manuelle*) of a VAL 206 trainset, on a 1.5 km test track with three stations.
The switch nomenclature and pupitre layout follow those discussed in the
electronics build-log video that motivated the project.

---

## 2. Theory of Operation

### 2.1 Vehicle

- Two-car articulated trainset, 26 m long, 2.06 m wide.
- Rubber tires running on twin concrete curbs flanking a **central yellow
  guide rail**.
- Three pairs of bi-parting passenger doors per car side (six per car).
- Maximum line speed 80 km/h; PA-mode cruise limited to 60 km/h.

### 2.2 Operating Modes

The VAL fleet operates in two mutually exclusive modes:

| Mode | Name | Description |
|------|------|-------------|
| **PA** | Pilotage Automatique | The train drives itself between stations. Vigilance device is bypassed. Normal revenue-service mode. |
| **PM** | Pilotage Manuel | The driver uses the master controller. Vigilance (KACOP) acknowledgments are required. Used for yard moves, recovery, fault recovery, and training. |

Mode is selected with the **PA** toggle on the pupitre. When PA is on, it
overrides the master-controller value entirely.

### 2.3 K-Series Switches

In French electrical convention, control switches are prefixed `K`
(for *contacteur*). The pupitre carries four, plus the **NAV** selector:

| Symbol | Expansion | Function |
|--------|-----------|----------|
| **KG** | Coupure Générale | Master power isolation. Without KG no traction or auxiliaries. |
| **KIBS** | Inhibition Boucle de Sécurité | Bypasses the safety interlock loop. Required for some recovery moves. |
| **KPH** | PHares | Headlights. |
| **PA** | Pilote Automatique | Selects automatic vs manual operation. |
| **NAV** | NAVette | Shuttle service: PA turns back on its own at each terminus. On-screen only — no HID button. |

### 2.4 Vigilance Device (KACOP)

**KACOP** — *Acquittement Conduite OPérateur* (operator-driving
acknowledgment) — is the dead-man button.

Under manual driving, the driver must momentarily press it **at least once
every 14 seconds**. The system detects the **rising edge** of the press
(release → press transition), so a wedged-down button does not satisfy the
requirement.

- Acknowledgment → `deadmanTimer = 0`
- **14 s** of running without acknowledgment: vigilance warning (red ring +
  1500 Hz buzzer gated at 4 Hz).
- **20 s**: emergency brake automatically applied.
- **PA mode bypasses the vigilance device entirely** — the whole point of an
  automatic metro is that no driver vigilance is required.

### 2.5 Master Controller (Manipulateur T/F)

A single vertical lever combining traction and braking:

- **+1** (top): full traction request (≈ 1.3 m/s²).
- **0** (center): coast — rolling resistance only (≈ 0.12 m/s²).
- **−1** (bottom): full service brake (≈ 1.4 m/s²).

Traction is inhibited when any of the following is true:

- KG is off,
- the reverser is in neutral,
- the emergency brake is latched,
- any passenger door is more than 2 % open.

Service braking is always available regardless of KG.

### 2.6 Reverser (Manipulateur d'Inversion)

Three positions:

| Position | Meaning |
|----------|---------|
| **AV** | Avant (forward) |
| **0** | neutral / isolated |
| **AR** | Arrière (reverse) |

The reverser must leave neutral before traction is enabled.

### 2.7 Stations & Doors

Three stations on the test track:

| Marker | Name | Position |
|--------|------|----------|
| P25 | QUATRE-CANTONS | 250 m |
| P75 | RÉPUBLIQUE | 750 m |
| P125 | GRAND-PLACE | 1 250 m |

Position is shown as `P000 / 150` (each unit = 10 m).

**Door interlock** — all conditions required:

- KG on,
- speed < 0.1 m/s,
- within ±6 m of a station center.

When met, the **DOORS OK** indicator on the pupitre lights green.

| Button | Meaning |
|--------|---------|
| **PO G** | Porte Ouverture Gauche (open driver's left) |
| **PO D** | Porte Ouverture Droite (open driver's right) |
| **FP** | Fermeture Portes (close all doors) |

Doors animate over 0.9 s. Traction is interlocked while any door is open.

### 2.8 PA Control Profile

`SimulationModel.computePAController` implements a closed-loop
constant-deceleration profile onto the platform mark:

1. Take the **latched target station** — the next one ahead in the current
   direction, skipping the station just served. The latch means creeping a few
   centimetres past the mark cannot make PA give up on the platform and set off
   for the next one.
2. Compute the deceleration that would bring the train to rest on the mark:
   `a = v² ⁄ 2d`, where `d` is the distance still to run.
3. If `a ≥ 1.0 m/s²`, brake with the fraction of the service brake that
   delivers exactly that — `−a ⁄ 1.4`, clamped to **−1.0**. Recomputing it every
   frame is what makes the stop accurate; a fixed notch held until the train
   happens to stop leaves it metres short.
4. Otherwise, if `a ≥ 0.5 m/s²`, command **0** (coast in).
5. Otherwise, if `v < 60 km/h`, command **+0.7** (70 % traction).
6. Otherwise, command **0** (cruise).
7. Inside ±0.05 m of the mark, command **−1.0** (full brake) until stopped.

Step 3 is latched with a Schmitt trigger: once braking, PA keeps braking until
`a` falls below 0.5 m/s². Braking at exactly the rate the profile asks for pins
`a` to the trigger point, so a single threshold would chatter the command — and
with it the FREIN voyant — frame by frame.

Berthing accuracy is about **±0.02 m** from the platform centre, and holds
after a disturbance (EB trip on the approach, door cycle) — PA re-runs the
profile from wherever the train ends up.

PA suspends whenever doors open or the EB is latched and resumes when those
conditions clear.

**Station sequencing.** `SimulationModel.updatePAStationSequence` drives the
arrival/departure cycle, because the profile above on its own would hold the
brake forever on the platform it just stopped at:

1. **Berth** — stopping (< 0.1 m/s) inside the ±6 m box of a station not yet
   served berths the train there; PA holds full brake.
2. **Dwell** — the berth is held for **10 s**. Opening the doors pauses the
   dwell; closing them with **FP** ends it at once.
3. **Depart** — the station is marked served and excluded as a stop target, so
   the profile picks the next one. The exclusion is released once the train is
   more than 12 m clear, letting the station be served again after a reverser
   change.

Turning **PA** off, cutting **KG**, or moving the reverser to **0** resets the
sequence; a suspension (doors, EB) does not — the berth survives it.

**Terminus.** The last station in the direction of travel *is* the terminus: PA
stays berthed there and holds the platform rather than running on to the end of
track. Moving the reverser to the opposite direction releases the berth and PA
works back down the line. PA engaged where there is no station ahead at all
simply holds the brake until the reverser is changed.

**Shuttle (NAV).** With **NAV** on, PA does the turnback itself: once the
terminus dwell is over (10 s, or at once after an **FP** door cycle) it throws
the reverser to the opposite direction — the pupitre's reverser follows — and
works back down the line, end to end, indefinitely. Engaged past the last
platform, it brakes to a stand, turns back and serves that platform first.
Turning NAV off mid-run lets the train finish its current leg and hold at the
next terminus.

### 2.9 Emergency Brake (Frein d'Urgence)

A latched key-protected mushroom button (**ARRÊT**).

- First press: brake applied at 2.8 m/s², URG voyant illuminates, brake
  hiss runs at maximum amplitude, traction inhibited.
- Second press: brake released.
- Also auto-applied when the dead-man timer exceeds 20 s in PM.

### 2.10 Voyants (Indicator Lights)

| Voyant | Color | Lit when |
|--------|-------|----------|
| **TRAC** | green | Traction commanded |
| **FREIN** | orange | Service brake commanded |
| **HM** | yellow | Veille acknowledged or dead-man alert |
| **PM** | cyan | Pilotage Manuel active (KG on, reverser ≠ 0, PA off) |
| **PA** | mint | Pilotage Automatique selected (KG on) |
| **PORT** | blue | At least one door is open |
| **URG** | red | Emergency brake latched |

### 2.11 Audio

Every voice is **synthesized live** from a single `AVAudioSourceNode` — no
audio samples shipped:

| Voice | Synthesis |
|-------|-----------|
| Motor whine | Dual-harmonic triangle wave; fundamental 32 → 352 Hz with speed; amplitude scales with traction request. |
| Brake hiss | Low-pass-filtered XOR-shift noise. |
| Horn (AVA) | 220 Hz fundamental + 1.5× harmonic. |
| Compressor | 55 Hz sine while KG is on. |
| Vigilance buzzer | 1500 Hz sine gated at 4 Hz, only during dead-man warning. |
| Door chime | 660 Hz sine envelope on every door-state transition. |

Output is soft-clipped through `tanh` to protect speakers at full output.
Master mute via the 🔊 button in the status bar.

### 2.12 USB HID Input

The simulator opens any HID joystick / gamepad / multi-axis controller it
detects through `IOHIDManager`. The Raspberry Pi Pico-based pupitre described
in the build-log video, presented as a 12-button + 1-axis HID gamepad, is
plug-and-play compatible with the default mapping:

| HID input | Simulator function |
|-----------|--------------------|
| Button 1 | KG |
| Button 2 | KACOP |
| Button 3 | KIBS |
| Button 4 | KPH |
| Button 5 | Horn (AVA) |
| Button 6 | PO G |
| Button 7 | PO D |
| Button 8 | FP |
| Button 9 | Reverser AV |
| Button 10 | Reverser 0 |
| Button 11 | Reverser AR |
| Button 12 | Emergency Brake (toggle) |
| Y axis | Master Controller — stick forward = +traction |

Connected device name appears in the HUD beside `PUPITRE USB:`. With no
device connected, mouse input on the on-screen pupitre is fully functional.

---

## 3. Operating Procedures

### 3.1 Cab Activation

1. Turn the **KG** key switch to on. The compressor hum starts.
2. Set the **reverser** to **AV** (forward) or **AR** (reverse).
3. Turn on **KPH** if running in low-light conditions.
4. Choose mode:
   - For automatic running, flip **PA** on — the train begins moving on its
     own.
   - For manual driving, leave PA off and use the master controller.

### 3.2 Manual Driving (PM)

1. Drag the master controller upward toward **TRAC** to accelerate. The
   TRAC voyant illuminates.
2. Tap **KACOP** at least once every 14 s. The countdown ring around it
   shows time remaining.
3. To brake, drag the master controller downward toward **FREIN**.
4. As you approach a station, brake to a stop. The DOORS OK indicator
   lights when conditions are met.

### 3.3 Station Stop and Door Operation

1. Verify **DOORS OK** is lit (green).
2. Press **PO G** to open driver's-left doors (a chime sounds).
3. Press **PO D** to open driver's-right doors.
4. When ready to depart, press **FP** to close all doors.
5. Wait for doors fully closed (PORT voyant extinguishes).
6. Proceed with traction.

### 3.4 Automatic Running (PA)

1. With KG on and the reverser out of neutral, flip **PA** on.
2. The train accelerates to 60 km/h, cruises, and brakes to a stop at the
   next station.
3. While stopped, operate doors as in §3.3.
4. After **FP** closes doors, PA picks up driving to the next station.
5. If you leave the doors shut, PA departs on its own after the 10 s dwell and
   works the line station by station, berthing within a couple of centimetres
   of each platform mark.
6. At the last station in the direction of travel PA stays berthed. Move the
   reverser to the opposite direction to work back down the line — or flip
   **NAV** on and PA shuttles between the two termini by itself, reversing
   after each terminus dwell.

### 3.5 Emergency Stop

1. Strike the **ARRÊT** mushroom button. URG voyant lights, train brakes at
   maximum rate.
2. The brake stays latched until the button is pressed again.
3. Investigate cause before releasing.

### 3.6 Recovery

If stopped between stations under PA (e.g. EB has tripped):

1. Release the emergency brake.
2. Either continue in PA or flip PA off and drive manually.

---

## 4. Glossary

- **Acquittement** — acknowledgment.
- **AVA** — *AVertisseur Acoustique* (horn).
- **Boucle de Sécurité (BS)** — safety interlock loop.
- **Coupure** — cutoff / isolation.
- **FP** — *Fermeture Portes*.
- **K-** — prefix denoting *contacteur* (contactor) in French electrical
  schematics.
- **Manipulateur** — controller / handle.
- **Navette (NAV)** — shuttle service between the two termini.
- **PA / PM** — *Pilotage Automatique / Manuel*.
- **PO G / PO D** — *Porte Ouverture Gauche / Droite*.
- **Pupitre** — cab control desk.
- **Veille** — vigilance / dead-man device.
- **Voyant** — indicator light.
