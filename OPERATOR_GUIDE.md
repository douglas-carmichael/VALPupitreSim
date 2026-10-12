# VAL 206 — Guide d'Exploitation & Théorie de Fonctionnement

*Operator's Guide & Theory of Operation for the **VALPupitreSim** macOS application.*

This document is the source-of-truth reference for the in-app guide (see
`OperatorGuideView.swift`). Update both together.

## Contents

1. [Introduction](#1-introduction)
2. [Theory of Operation](#2-theory-of-operation)
   - [2.1 Vehicle](#21-vehicle) · [2.2 Operating Modes](#22-operating-modes) ·
     [2.3 K-Series Switches](#23-k-series-switches) ·
     [2.4 Vigilance Device (KACOP)](#24-vigilance-device-kacop)
   - [2.5 Master Controller](#25-master-controller-manipulateur-tf) ·
     [2.6 Reverser](#26-reverser-manipulateur-dinversion) ·
     [2.7 Stations & Doors](#27-stations--doors) ·
     [2.8 PA Control Profile](#28-pa-control-profile)
   - [2.9 Emergency Brake](#29-emergency-brake-frein-durgence) ·
     [2.10 Voyants](#210-voyants-indicator-lights) · [2.11 Audio](#211-audio) ·
     [2.12 USB HID Input](#212-usb-hid-input) · [2.13 Displays](#213-displays) ·
     [2.14 PCC Link](#214-pcc-link-commande-pcc)
3. [Operating Procedures](#3-operating-procedures)
4. [Glossary](#4-glossary)

---

## 1. Introduction

The **VAL** (*Véhicule Automatique Léger*) is a rubber-tired automated metro
system developed by **Matra Transport** for the Lille Métropole network and
placed in revenue service in 1983. The **VAL 206** variant takes its name
from the body width of its vehicles: **2.06 m**.

This simulator reproduces the **manual-driving cab** (*pupitre de conduite
manuelle*) of a VAL 206 trainset, on a 1.5 km test track with three stations —
or, under PCC command, on the line a PCC lends it, among that line's other
rames (§2.14).
The switch nomenclature and pupitre layout follow the replica pupitre shown
in **La Patate Douce**'s video
[*Pupitre VAL 206 : Simulation de conduite manuelle*](https://www.youtube.com/watch?v=U4T-fxTc7go),
which inspired the project.

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
| **KIBS** | Inhibition Boucle de Sécurité | On a real VAL, bypasses the safety interlock loop for some recovery moves. Present on the pupitre but not yet simulated — it has no effect. |
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
- The timer only counts while the train is *running* under manual control:
  KG on, reverser out of neutral, speed above 0.5 m/s (≈ 1.8 km/h). Otherwise
  it winds back down at twice the rate.
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

Service braking is **not** subject to these traction interlocks: it works with
the doors open, the reverser in neutral, and so on.

With **KG off** the train is unpowered. Neither the service brake nor the
emergency brake acts, and the train only drifts to a stop on residual
resistance (≈ 0.05 m/s²).

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

Position is shown as `P000 / 150` (each unit = 10 m). It locates the centre
of the leading car (car 1, at the AV end): that is the point PA stops on the
platform mark.

On a PCC's line (§2.14) the stations are the PCC's, and the position reads
against that line's length — `P085 / 100` on a 1 km loop.

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

Doors animate over 0.9 s, with a chime when they start to open or close.
Traction is interlocked while any door is open. If the train moves off
anyway (above 0.3 m/s, e.g. drifting with KG off), the doors close by
themselves.

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

**PCC stopping point.** When the PCC has set a stopping point (§2.14) that
comes before the next station, PA brakes onto it exactly as onto a platform
mark, and waits there until the PCC moves it on.

**Loops.** On a PCC's loop there is no terminus: PA serves the stations lap
after lap, and NAV has nothing to do.

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
- Also auto-applied when the dead-man timer exceeds 20 s in PM, and — under
  PCC command — when the link to the PCC is lost or the rame runs past the
  PCC's stopping point (§2.14). Any connected PCC can apply it too.
- When something other than ARRÊT latched it, the station bar names the
  cause (§2.13).
- Like the service brake, it needs **KG** on to act (see §2.5).

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
| Motor whine | Dual-harmonic triangle wave. The fundamental runs 32 → 352 Hz with speed, and the amplitude rises with speed, boosted 25 % while traction is commanded. |
| Brake hiss | Low-pass-filtered XOR-shift noise, louder with brake demand and loudest under the emergency brake. |
| Horn (AVA) | 220 Hz fundamental + 1.5× harmonic. |
| Compressor | 55 Hz sine while KG is on. |
| Vigilance buzzer | 1500 Hz sine gated at 4 Hz, only during dead-man warning. |
| Door chime | 660 Hz decaying sine when doors start to open or close. |

Output is soft-clipped through `tanh` to protect speakers at full output.
Mute and unmute with the speaker button in the status bar.

### 2.12 USB HID Input

The simulator opens any HID joystick / gamepad / multi-axis controller it
detects through `IOHIDManager`. A Raspberry Pi Pico-based pupitre like the one
in La Patate Douce's video (see §1), presented as a 12-button + 1-axis HID
gamepad, is plug-and-play compatible with the default mapping:

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

How each input behaves:

- **Buttons 1, 3, 4** (KG, KIBS, KPH) follow the button *level*: the switch
  is on for as long as the input is held. Wire them to latching switches.
- **Buttons 2, 5–8** (KACOP, horn, doors) are momentary. KACOP and the door
  buttons act on the press edge only.
- **Buttons 9–11** set the reverser position on press.
- **Button 12** toggles the emergency brake on each press.

Under PCC command (§2.14) the HID pupitre is locked out like the on-screen
one: only button 12 still acts. Latching switches wired to buttons 1, 3 and 4
may disagree with what the PCC set; toggle them after taking the cab back.

The connected device's name appears in the HUD beside `PUPITRE USB:`. With
no device connected, mouse input on the on-screen pupitre is fully
functional.

### 2.13 Displays

The main window, from top to bottom:

| Area | Shows |
|------|-------|
| Status bar | Position, speed (km/h), master-controller value, the **PA** badge (**PA STBY** when PA is selected but suspended), the **COMMANDE** selector (§2.14), the mute button and the reverser position. Also holds the guide (📖) and **VUE CABINE** buttons. |
| Station bar | Current station or next stop and its distance; a **POINT D'ARRÊT** pill with the distance to the PCC's stopping point, red within 30 m; a **FREIN D'URGENCE** pill naming the cause when something other than ARRÊT latched the emergency brake (VEILLE (KACOP), COMMANDÉ PAR LE PCC, PERTE DE LIAISON PCC, POINT D'ARRÊT FRANCHI); the USB pupitre status; the **PCC** link pill (§2.14); and a **VIGILANCE** alert during a dead-man warning. |
| Track overview | Top-down map of the whole line with the train marker (white and green, with an orange arrow for the direction of travel). A PCC's loop is drawn as a racetrack with its cantons ticked off and its name in the middle; the other rames the PCC reports appear as blue markers carrying their numbers. |
| Chase camera | 3D view of the train on the guideway — straight on the test track, a circle on a PCC's loop. Headlights follow **KPH**. The other rames on a PCC's line run on the same guideway, numbered. |
| Pupitre | The control desk: switches, reverser, master controller, voyants, push buttons, KACOP, speedometer and emergency brake. Under PCC command everything but ARRÊT is locked, and a green banner says so. |

**VUE CABINE** opens a separate window with the driver's-eye view and a HUD
overlay, which also shows the distance to the PCC's stopping point. On a PCC's
line the rame ahead is in sight — its red tail lamps first.

### 2.14 PCC Link (Commande PCC)

A **PCC** (*Poste de Commande Centralisé*) — such as the metroSystem
dispatcher — can find the cab on the local network, follow it, and command
it. The protocol is specified in [`PCC_API.md`](PCC_API.md).

**Discovery.** The cab advertises itself over Bonjour (`_valpupitre._tcp`) as
`Rame <number> — <computer name>` and listens on TCP port 5206 (any free port
if 5206 is taken). On first launch macOS asks whether the app may use the
local network: allow it, or PCCs won't find the cab.

**COMMANDE selector.** The status bar's selector chooses who drives:

| Position | Meaning |
|----------|---------|
| **LOCALE** | The pupitre drives (the default). PCCs may follow the cab and apply its emergency brake, nothing more. |
| **PCC** | The PCC in command drives. The pupitre and the USB HID pupitre are locked — they show what the PCC sets but don't respond — except **ARRÊT**, which stays live. |

Only the cab can move the selector, and it keeps its position across
launches.

**One PCC in command.** Several PCCs may be connected at once. One of them
takes control, and only its commands are applied: KG, KIBS, KPH, PA, NAV, the
reverser (at a stand only), the master controller, KACOP, the door buttons and
the emergency brake. Any connected PCC may apply the emergency brake,
whichever way the selector is set.

**Link watchdog.** Under PCC command the cab must keep hearing from its PCC.
After **3 s** of silence — the link is lost, the PCC has gone quiet, or no PCC
has taken control — it applies the emergency brake: fail-safe by absence. The
brake stays latched when the link returns; the PCC or ARRÊT releases it. A cab
switched to PCC before any PCC has connected therefore waits, braked, for one
to take over.

**Same rules as the pupitre.** The PCC drives under the cab's interlocks:
traction is cut by KG, the reverser, the emergency brake and the doors, and
in PM the PCC has to acknowledge KACOP like a driver.

**The PCC's line.** A PCC can lend the rame its own line — metroSystem lends
its 1 km loop. Once the cab is under PCC command and at a stand, the rame
moves onto that line where the PCC puts it (metroSystem picks the station
farthest from its own trains), and every view redraws for it: the chase and
cab views follow the loop round, and the map shows it as a racetrack with its
cantons and its name. The station bar and the HUD then count down to that
line's stations.

**Stopping point (point d'arrêt).** The PCC can give the rame a point it must
not pass — metroSystem puts it 8 m short of the first block ahead held by
another rame, as its fixed-block wayside does for its own trains. The
**POINT D'ARRÊT** pill shows how far there is to go. PA stops on it; driving
past it (more than 1 m, still moving) latches the emergency brake —
**POINT D'ARRÊT FRANCHI**.

**Other rames.** The PCC can also tell the cab where the line's other rames
are. They appear in the chase and cab views as rames like this one, with their
number above them, white lamps at the end leading and red at the end
trailing, and on the map as blue numbered markers. Between the PCC's reports
they move on at their last reported speed; if the reports stop for 2 s they
disappear. They are for display only: it is the PCC's stopping point that
keeps the rame clear of them.

**Telemetry.** The cab streams its rame's instruments to every connected PCC
along with its state: the traction chain (line voltage and current, armature
and field currents, chopper duty, torque, regeneration) and the auxiliaries
(converter, battery, lighting, compressor and main reservoir, brake-box
temperature). They are worked out from what the simulation is doing, with
the VAL 206's traction-chain figures, so metroSystem's train-detail synoptic
shows real values for the rame. They don't affect the driving.

**Taking the cab back.** Turn the selector to **LOCALE** at any time; the PCC's
commands are refused from then on. A rame on the PCC's line returns to the
test track, stopped where it left it; the stopping point and the other rames
go with the PCC.

**PCC pill.** The station bar's **PCC** pill sums up the link:

| Colour | Meaning |
|--------|---------|
| grey | Under LOCALE command, no PCC connected. |
| yellow | Under LOCALE command, with PCCs connected. |
| green | Under PCC command, with the PCC in command named. |
| red | Under PCC command without a PCC (EN ATTENTE DU PCC), or the link has failed. |

Click it for the details: the Bonjour name, the port, the connected PCCs, and
the **rame number** the cab presents to them. By default that number lies
between 301 and 399 and stays the same for a given Mac. Edit it and press
Return. Give each cab its own number when several share a network.

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

### 3.7 Handing the Cab to the PCC

1. Start the PCC (metroSystem) on the same local network. The **PCC** pill
   turns yellow once it has connected.
2. Turn the **COMMANDE** selector to **PCC**. The pupitre locks, and the PCC
   pill turns green and names the PCC once it has taken control.
3. The PCC now drives. If no PCC takes control within 3 s, the emergency
   brake latches (PERTE DE LIAISON PCC) until a PCC releases it.
4. metroSystem moves the rame onto its loop, at a station, and the views show
   its trains. From there metroSystem's operator puts the rame in service.
5. In an emergency, strike **ARRÊT**: it always works.
6. To take the cab back, turn the selector to **LOCALE**. The rame returns to
   the test track.

---

## 4. Glossary

- **Acquittement** — acknowledgment.
- **AVA** — *AVertisseur Acoustique* (horn).
- **Boucle de Sécurité (BS)** — safety interlock loop.
- **Canton** — block: a fixed section of line that one rame holds at a time.
- **Coupure** — cutoff / isolation.
- **FP** — *Fermeture Portes*.
- **K-** — prefix denoting *contacteur* (contactor) in French electrical
  schematics.
- **Manipulateur** — controller / handle.
- **Navette (NAV)** — shuttle service between the two termini.
- **PA / PM** — *Pilotage Automatique / Manuel*.
- **PCC** — *Poste de Commande Centralisé*: the central control post that
  supervises the line's trains.
- **PO G / PO D** — *Porte Ouverture Gauche / Droite*.
- **Point d'arrêt** — stopping point: where the PCC requires the rame to stop.
- **Pupitre** — cab control desk.
- **Rame** — trainset.
- **Veille** — vigilance / dead-man device.
- **Voyant** — indicator light.
