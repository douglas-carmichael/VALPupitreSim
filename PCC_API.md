# VALPupitreSim PCC Link — API Specification

*Protocol version 1.* The network interface through which a **PCC** (*Poste de
Commande Centralisé*, the central control post) — metroSystem, or any program —
finds VALPupitreSim cabs on the local network, monitors them and, when a cab is
handed over to it, commands it and runs it on its own line.

Implemented in `VALPupitreSim/PCCLink.swift` (server) and
`VALPupitreSim/PCCProtocol.swift` (wire types). This document is the
specification; change it together with those two files. The operator's side —
the COMMANDE selector, the lock-out, the HUD — is described in
[`OPERATOR_GUIDE.md`](OPERATOR_GUIDE.md) §2.14.

## Contents

1. [Overview](#1-overview)
2. [Discovery](#2-discovery)
3. [Transport and framing](#3-transport-and-framing)
4. [Session lifecycle](#4-session-lifecycle)
5. [Authority and control](#5-authority-and-control)
6. [The PCC's line](#6-the-pccs-line)
7. [Messages from the PCC](#7-messages-from-the-pcc)
8. [Commands](#8-commands)
9. [Messages from the cab](#9-messages-from-the-cab)
10. [State reference](#10-state-reference)
11. [Events reference](#11-events-reference)
12. [Error codes](#12-error-codes)
13. [Operating recipes](#13-operating-recipes)
14. [Cab configuration](#14-cab-configuration)
15. [Integrating with metroSystem](#15-integrating-with-metrosystem)
16. [Example session](#16-example-session)
17. [Versioning](#17-versioning)

---

## 1. Overview

Each running VALPupitreSim is one **cab** driving one rame — on its own 1.5 km
test track, or, under PCC command, on a line the PCC lends it. The cab is the
**server**: it advertises itself over Bonjour and accepts TCP connections. A
PCC is a **client**, and so is anything else that connects — a monitoring
script, `nc`.

- **Monitoring is open.** Every connected session receives the cab's state ten
  times a second and an event whenever something notable happens.
- **The cab decides who commands it.** Its **COMMANDE** selector reads
  **LOCALE** (the pupitre drives — the default) or **PCC** (the network
  drives). Only the cab's operator can move it; a PCC cannot.
- **One PCC at a time.** A session must **acquire control** before it can
  command. Commands are applied only when the session holds control *and* the
  selector is on PCC.
- **Any PCC can stop the train.** Applying the emergency brake is accepted from
  every session, in either mode.
- **Fail-safe by absence.** Under PCC command the cab needs to keep hearing
  its controlling PCC. After 3 s of silence it applies the emergency brake.
- **The PCC can bring its own line.** The PCC in command can put the rame on
  its line (a loop, typically), give it a stopping point it must not pass, and
  tell it where the line's other rames are so that the cab shows them (§6).

## 2. Discovery

| Item | Value |
|------|-------|
| Bonjour service type | `_valpupitre._tcp` in `local.` |
| Instance name | `Rame <number> — <computer name>`, at most 63 bytes. mDNS renames on a clash (`… (2)`), so treat it as display text. |
| Port | **5206** by default. If 5206 is taken (a second cab on the same Mac), the cab takes any free port. **Always use the port from the Bonjour resolution.** |
| Interfaces | All interfaces (Ethernet, Wi‑Fi). The cab can be restricted to this Mac with `pccLoopbackOnly` (§14). |

The TXT record lets a PCC identify a cab before connecting:

| Key | Example | Meaning |
|-----|---------|---------|
| `proto` | `1` | Protocol version (§17). Skip cabs with a version you don't speak. |
| `id` | `6F1C9A2E-…` | Stable cab identity (a UUID kept across launches). **Key your fleet on this**, not on the name or rame number. |
| `rame` | `301` | Rame number, as set in the cab. |
| `app` | `VALPupitreSim` | Producing application. |

From the command line:

```sh
dns-sd -B _valpupitre._tcp                           # browse
dns-sd -L "Rame 301 — Mac Studio" _valpupitre._tcp   # resolve host, port, TXT
```

**macOS Local Network privacy.** macOS holds a Bonjour advertisement until the
user allows the app to use the local network. The prompt appears the first
time each Mac runs the cab. Until it is allowed, the cab still accepts
connections by address and port but isn't discoverable. A PCC application that
*browses* needs the same permission and must list `_valpupitre._tcp` under
`NSBonjourServices` in its Info.plist.

## 3. Transport and framing

- **TCP**, keepalive enabled (10 s idle, 5 s interval, 3 probes), no TLS.
- **One JSON object per line**, UTF-8, terminated by LF (`\n`). A CR before
  the LF is ignored; blank lines are skipped. A line may not exceed **64 KiB**
  (`lineTooLong`, then disconnection).
- Every object has a **`type`**. The cab writes `type` first and the other
  keys in sorted order, which keeps captures readable. Don't rely on key order
  when parsing.
- **Optional fields are omitted** when they have no value; the cab never sends
  `null`. **Ignore fields and event names you don't recognise** — new ones are
  added without a version change (§17).
- **Units** are SI and named in the field: `…M` metres, `…MS` m/s, `…MS2`
  m/s², `…S` seconds, `…V` volts, `…A` amperes, `…Bar` bar, `…C` °C,
  `…Pct` percent. Values are rounded (positions to the millimetre).
  Station indices are 0-based and match `stations[].index` in the cab's line
  description (`hello.line`, the `line` event).
- At most **8 sessions** per cab. A ninth connection receives
  `tooManySessions` and is closed.
- A client may disconnect at any time. If it half-closes its side (sends FIN),
  the cab answers everything it sent, then closes.

There is **no authentication**. Anyone on the network can monitor a cab and
apply its emergency brake. Run cabs on a trusted network, or set
`pccLoopbackOnly`.

## 4. Session lifecycle

```
PCC                                         cab
 │── TCP connect ─────────────────────────────▶│
 │◀───────────────────────────────── hello ─────│  at once: identity, line, geometry, limits
 │◀──────────────────── state (10 Hz) ──────────│  at once, until disconnection
 │── hello (name, protocol, rate) ────────────▶│  optional but recommended
 │◀──────────────────────────────── result ─────│
 │── acquire ─────────────────────────────────▶│  to command
 │◀──────────────────────────────── result ─────│
 │◀──────────────────────── event control ──────│  to every session
 │── ping, at least every second ─────────────▶│  while holding control
 │◀────────────────────────────────── pong ─────│
 │── line (optional) ─────────────────────────▶│  under PCC command, at a stand
 │◀──────────────────────────────── result ─────│
 │◀──────────────────────────── event line ─────│  to every session
 │── command ─────────────────────────────────▶│
 │◀──────────────────────────────── result ─────│
 │── traffic, ~5 Hz (optional) ───────────────▶│  the line's other rames
 │◀──────────────────────────────── result ─────│
 │◀─────────────────────────── event … ─────────│  as things happen
```

Messages on a session arrive in order. A request's `result` is sent before any
event or state that shows its effect. A `result` with `"ok": true` means the
request was accepted and applied to the cab's inputs. Its effect shows in the
next `state` (about 16 ms later, then at the next sample), still subject to
the simulator's own interlocks (§8).

## 5. Authority and control

### 5.1 The COMMANDE selector

| `authority` | The cab… |
|-------------|----------|
| `local` | is driven from its pupitre, on its own test track. PCCs may monitor and apply the emergency brake; every other request is refused with `localAuthority`. |
| `pcc` | takes its commands from the controlling PCC. The on-screen pupitre and the USB HID pupitre are **locked**, except **ARRÊT** (the emergency brake), which stays live at the cab. The link watchdog (§5.3) runs. |

The selector sits in the cab's status bar. Its position survives a relaunch,
like a real key switch. A change is reported to every session as an
`authority` event and in `state.control.authority`.

### 5.2 Control

At most one session **holds control** at a time.

- `acquire` takes control when nobody holds it. If another session holds it,
  the request is refused with `controlHeld` and the holder's name — unless it
  carries `"force": true`, which **preempts** the holder.
- `release` gives control up.
- Control may be held under either authority. A PCC that acquires a cab in
  LOCALE is in command the moment the operator turns the selector to PCC.
- A session loses control when it releases it, disconnects, is preempted, or
  stays **silent for 3 s** (timeout).

Every change of holder is announced to every session (`control` event, §11)
and shows in `state.control.holder`, with `state.control.you` true for the
holder.

### 5.3 Link watchdog

The controlling session must send at least one line every second — a `ping`
when it has nothing else to say. Any line counts.

Under PCC command the cab counts the silence from its controller
(`state.control.silenceS`). Past **3 s** the cab applies the emergency brake
with cause **`pccLink`**, and a silent controller loses control. That covers a
controller that has gone quiet, has disconnected, or was never there.

- The brake **stays latched** when the link comes back. The PCC (or ARRÊT at
  the cab) has to release it. In particular, a cab switched to PCC before any
  PCC connected is already braked (`pccLink`) when a PCC takes over, so
  taking over starts by releasing it (§13).
- Under LOCALE command the watchdog doesn't run (`silenceS` stays 0). A silent
  holder still loses control after 3 s.

### 5.4 The safety exception

`{"type":"command","command":"emergencyBrake","value":true}` is accepted from
**any** session, in **either** authority, with or without control: any PCC
can always stop the train. Releasing the brake is an ordinary command — PCC
authority and control are required.

### 5.5 What the cab's operator keeps

Under PCC command the person at the cab can still:

- strike **ARRÊT** to apply or release the emergency brake (reported with
  cause `cab`);
- turn the selector back to **LOCALE** at any moment, taking the cab back
  (*reprise en local*): PCC requests are refused from then on, and the rame
  returns to its test track (§6.1);
- renumber the rame.

## 6. The PCC's line

### 6.1 Lending a line

The cab starts on its own straight test track (`line.id` `test-track`, 1.5 km,
three stations). Under PCC command, the controlling PCC can put the rame on a
line of its own with a `line` message (§7): an id, a length, whether it is a
loop, its stations and, optionally, its blocks (cantons). The rame joins it,
from a stand, at the position the PCC gives, and runs on it for as long as the
cab stays under PCC command.

- Sending the line the rame is already on (the same `id`) changes nothing, so
  a PCC can send its line every time it takes control.
- Joining a line leaves the rame at a stand with its doors shut, resets PA's
  station sequence, and clears the stopping point (§6.3) and the traffic
  (§6.4). KG, the reverser and the PA selector stay as they were.
- Every session gets a `line` event with the full description, and
  `state.line` changes.
- When the cab's operator turns the selector back to **LOCALE**, the rame
  returns to its test track, at a stand where it left it (another `line`
  event).
- **Loops.** Positions run from 0 up to, but not including, `lengthM`, and
  wrap round. PA serves the stations lap after lap; there is no terminus.
  Stations, distances and the stopping point are measured forward round the
  loop, except for the last 50 m behind the rame, which count as just passed.

The cab draws the line it is on. A loop appears in the chase and cab views as
a circle of the line's length, and on the map as a racetrack with its blocks
ticked off and its name in the middle.

### 6.2 Positions and geometry

Every position — `motion.positionM`, the stations, the stopping point, the
traffic — locates one reference point of a rame: the centre of **car 1**, the
car at the AV end. A VAL 206 is two 12.8 m cars, their centres 13.2 m apart,
so the rame reaches 6.4 m beyond its position towards higher positions (its AV
end) and 19.6 m back towards lower ones (its AR end): 26 m in all, whichever
way it runs. `hello.geometry` gives these figures:

| Field | Value | Meaning |
|-------|-------|---------|
| `lengthM` | 26 | Length of the rame. |
| `avEndM` | 6.4 | From the position to the AV end. |
| `arEndM` | 19.6 | From the position to the AR end. |

PA stops the reference point on the station's position. A PCC that places
rames by their head — the end leading in the direction of travel — converts:
running AV the head is at `positionM + avEndM`, running AR at
`positionM − arEndM`.

### 6.3 The stopping point

The controlling PCC can give the rame a stopping point (*point d'arrêt*) on its
line with the `limit` command (§8): a position the rame's reference point must
not pass. A PCC protecting its line moves it as the line ahead fills or
clears, as a fixed-block wayside does.

- **PA** brakes onto the stopping point when it comes before the next station,
  and waits there until the point moves on.
- **Running past it** — more than 1 m past, at more than 0.3 m/s — latches the
  emergency brake with cause **`limit`**. A point that the moving rame is
  already past trips the brake at once, so set it ahead.
- `limit` with no value lifts it. Joining or leaving a line lifts it too, and
  so does the selector going back to LOCALE.
- `state.limit` shows it while it is set. The cab's operator sees a
  **POINT D'ARRÊT** pill with the distance to go.

### 6.4 Traffic: the other rames

The controlling PCC can tell the cab where the other rames on its line are,
with `traffic` messages (§7). The cab draws each one as it draws itself — two
cars on the guideway in the chase and cab views, white lamps at its leading
end and red at its trailing end, its number above it — and as a numbered blue
marker on the map.

- Each message is the whole picture and replaces the last. An empty list
  clears it. Don't include the cab's own rame.
- Between messages the cab carries every rame forward at its reported speed,
  so they glide instead of jumping. Send at least once a second; five times a
  second looks smooth.
- A picture more than **2 s** old is dropped. It is also dropped when control
  changes hands, when the rame joins or leaves a line, and when the selector
  goes back to LOCALE.
- Traffic is for display only: the cab doesn't stop for these rames. Keeping
  it clear of them is the PCC's job, with the stopping point.

## 7. Messages from the PCC

Every request may carry an **`id`** — any string or number. The cab echoes it
in the `result` (or `pong`), so a client can match replies to requests.

### `hello`

Identifies the PCC. Optional, but recommended, because the name is what the
cab's operator sees.

| Field | Type | Meaning |
|-------|------|---------|
| `protocol` | integer | The protocol version the client speaks. Anything other than `1` is refused with `unsupportedProtocol`, and the connection is closed. |
| `name` | string | Display name of the PCC, up to 64 characters. It is shown at the cab and in `holder` fields. Default: the client's IP address. |
| `stateRateHz` | number | Rate of `state` messages for this session, 1–60 (clamped). Default 10. |

```json
{"type":"hello","id":1,"protocol":1,"name":"PCC Lille — Mac mini","stateRateHz":10}
```

### `acquire`

Takes control (§5.2). `"force": true` preempts the current holder.

```json
{"type":"acquire","id":2}
{"type":"acquire","id":3,"force":true}
```

### `release`

Gives up control. Refused with `notController` if this session doesn't hold
it.

```json
{"type":"release","id":4}
```

### `command`

| Field | Type | Meaning |
|-------|------|---------|
| `command` | string | One of the commands in §8. |
| `value` | string, number or boolean | The command's argument, when it takes one. |

```json
{"type":"command","id":5,"command":"reverser","value":"AV"}
```

### `line`

Lends the cab the PCC's line (§6.1). Requires PCC authority and control.

| Field | Type | Meaning |
|-------|------|---------|
| `line` | object | The line, as below. |
| `positionM` | number | Where the rame joins it (§6.2). Required unless the rame is already on this line. |

| `line` field | Type | Meaning |
|--------------|------|---------|
| `id` | string | Identifies the line: 1–64 characters, not `test-track`. The same id means the same line. |
| `name` | string? | Display name, shown on the cab's map. Default: the id. |
| `lengthM` | number | Length, 50–100 000 m. |
| `loop` | boolean | A loop: positions wrap round at `lengthM`. |
| `stations` | array | Up to 64 stations, each `{"name", "positionM"}`, with a name of 1–64 characters and a position on the line. The cab orders them by position; station indices follow that order. |
| `blocks` | array? | Up to 512 blocks (cantons), each `{"id", "startM", "lengthM"}`. Drawn on the map only. |

Refused with `badValue` when the description or the position doesn't fit (the
message says what), and with `notStopped` while the rame is moving.

```json
{"type":"line","id":6,"positionM":850,"line":{"id":"metroSystem-e08ce6e163d76bd5","name":"MetroSystem VAL","lengthM":1000,"loop":true,"stations":[{"name":"CHU - Eurasanté","positionM":50},{"name":"Gambetta","positionM":200},{"name":"Gare Lille Flandres","positionM":350},{"name":"Fives","positionM":550},{"name":"Pont de Bois","positionM":700},{"name":"4 Cantons","positionM":850}],"blocks":[{"id":1,"startM":0,"lengthM":100},{"id":2,"startM":100,"lengthM":100}]}}
```

(Abridged: metroSystem sends all ten blocks.)

### `traffic`

Where the other rames on the line are (§6.4). Requires PCC authority and
control.

| Field | Type | Meaning |
|-------|------|---------|
| `trains` | array | Up to 64 rames, as below. An empty list clears the picture. |

| Train field | Type | Meaning |
|-------------|------|---------|
| `rame` | string | Its number, 1–16 characters, shown above it. |
| `positionM` | number | Its position on the cab's current line, measured as the cab measures its own (§6.2). |
| `speedMS` | number? | Its speed, 0–100. Default 0. |
| `sense` | `"AV"` / `"AR"`? | The way it runs, as in `state.motion.sense`. Default `AV`. |

The whole message is refused with `badValue` if any rame in it doesn't fit; a
field of the wrong JSON type (a numeric `rame`, say) is a `badMessage`.

```json
{"type":"traffic","id":"traffic","trains":[{"rame":"101","positionM":43.6,"speedMS":0,"sense":"AV"},{"rame":"102","positionM":976.2,"speedMS":11.8,"sense":"AV"}]}
```

### `ping`

Keeps the link alive and checks it. The cab answers `pong` with the same `id`.

```json
{"type":"ping","id":7}
```

## 8. Commands

Apart from the safety exception (§5.4), every command requires PCC authority
(`localAuthority` otherwise) and control (`notController` otherwise).

| Command | `value` | Effect | Refused with |
|---------|---------|--------|--------------|
| `kg` | boolean | **KG** — master power. Without it nothing acts: no traction, no braking (the train only drifts down). | `badValue` |
| `kibs` | boolean | **KIBS** — safety-loop inhibition. Present on the pupitre but not yet simulated. | `badValue` |
| `kph` | boolean | **KPH** — headlights. | `badValue` |
| `pa` | boolean | **PA** selector — automatic (true) or manual (false) driving. PA only drives with KG on, the reverser out of neutral, the doors closed and the emergency brake released. | `badValue` |
| `nav` | boolean | **NAV** — PA turns back by itself at each terminus. | `badValue` |
| `reverser` | `"AV"`, `"0"`, `"AR"` or `1`, `0`, `-1` | Reverser position. Moves only at a stand (below 0.1 m/s). Setting the current position is always accepted. | `badValue`, `notStopped` |
| `masterController` | number, −1…+1 | The **T/F** lever: +1 full traction (1.3 m/s²), 0 coast, −1 full service brake (1.4 m/s²). Out-of-range values are clamped. PA ignores it while it drives. | `badValue` |
| `kacop` | — | One **KACOP** press: acknowledges the dead-man (a single rising edge). | — |
| `doorsOpen` | `"left"`, `"right"`, `"both"` | One press of **PO G**, **PO D** or both. | `badValue`, `doorsInterlocked` |
| `doorsClose` | — | One press of **FP** (close all doors). | `doorsInterlocked` |
| `emergencyBrake` | boolean | **ARRÊT** — true latches the emergency brake (2.8 m/s², cause `pcc`), false releases it. True is accepted from any session (§5.4). | `badValue` |
| `limit` | number, or none | The stopping point (§6.3): a position on the current line. No value lifts it. | `badValue` |

**Booleans** are `true`/`false`. Numbers are also accepted, read as metroSystem
sends its commands: above 0.5 is on.

**Door interlock.** Doors operate only with KG on, the train below 0.1 m/s and
within ±6 m of a platform centre — `state.doors.canOperate`. The cab refuses
door commands otherwise.

**The simulation's own rules still apply.** Traction is inhibited with KG off,
the reverser at 0, the emergency brake latched or any door more than 2 % open.
Service braking isn't subject to those interlocks. Under manual driving the
**dead-man** runs: while the train is running (KG on, reverser out of 0, above
0.5 m/s), a `kacop` is needed at least every **14 s** (`vigilance` warning),
or the emergency brake latches at **20 s** (cause `deadman`). PA bypasses the
dead-man. See `OPERATOR_GUIDE.md` §2 for the full theory of operation.

## 9. Messages from the cab

### `hello`

Sent once, as soon as the connection opens.

```json
{
  "type": "hello",
  "protocol": 1,
  "app": "VALPupitreSim",
  "appVersion": "1.0",
  "authority": "local",
  "cab": {
    "id": "6F1C9A2E-1D52-4B7A-9E0B-2B6C3D8E4F10",
    "rame": "301",
    "name": "Rame 301 — Mac Studio"
  },
  "commands": ["kg", "kibs", "kph", "pa", "nav", "reverser", "masterController",
               "kacop", "doorsOpen", "doorsClose", "emergencyBrake", "limit"],
  "geometry": {"lengthM": 26, "avEndM": 6.4, "arEndM": 19.6},
  "limits": {
    "maxSpeedMS": 22.2, "maxAccelerationMS2": 1.3, "serviceBrakeMS2": 1.4,
    "emergencyBrakeMS2": 2.8, "paCruiseMS": 16.7, "paDwellS": 10,
    "deadmanWarnS": 14, "deadmanLimitS": 20, "doorTravelS": 0.9
  },
  "line": {
    "id": "test-track",
    "name": "VOIE D'ESSAI",
    "lengthM": 1500,
    "loop": false,
    "stationToleranceM": 6,
    "stations": [
      {"index": 0, "name": "QUATRE-CANTONS", "marker": "P25",  "positionM": 250},
      {"index": 1, "name": "RÉPUBLIQUE",     "marker": "P75",  "positionM": 750},
      {"index": 2, "name": "GRAND-PLACE",    "marker": "P125", "positionM": 1250}
    ]
  },
  "link": {"stateRateHz": 10, "heartbeatS": 1, "timeoutS": 3}
}
```

| Field | Meaning |
|-------|---------|
| `cab.id` | Stable identity, the same as the TXT `id`. |
| `cab.rame` | Rame number (it can change: `cab` event). |
| `cab.name` | The Bonjour instance name. |
| `authority` | The selector's position when the session opened. |
| `line` | The line the rame is on: its test track, as here, or a PCC's line (§6.1). Stations carry their `index` and a `marker` (`P` and the position in tens of metres); `blocks` appear when the line has them. `stationToleranceM` is the half-width of a platform's stopping box. |
| `geometry` | Where the rame lies around its position (§6.2). |
| `limits` | The simulator's constants: performance, PA cruise and dwell, dead-man delays, door travel time. |
| `link` | Default state rate, the expected heartbeat interval, and the watchdog timeout. |
| `commands` | The commands this cab accepts. |

### `state`

The cab's complete picture, sent at the session's rate (10 Hz by default) and
sampled from its ~60 Hz physics loop. Field reference in §10.

### `event`

Something changed. `event` names it; the other fields depend on the event
(§11).

### `result`

The answer to every request but `ping`: `hello`, `acquire`, `release`,
`command`, `line` and `traffic`.

| Field | Meaning |
|-------|---------|
| `id` | The request's `id`, echoed (omitted if the request had none). |
| `ok` | `true` if the request was carried out. |
| `error` | When `ok` is false: the code (§12). |
| `message` | When `ok` is false: an English explanation for logs. |
| `holder` | With `controlHeld` and `notController`: who holds control. |

### `pong`

The answer to `ping`, with its `id`.

### `error`

A problem with the stream rather than a request: an unparseable line
(`badMessage`), or a line that is too long (`lineTooLong`), or too many
sessions (`tooManySessions`). The last two close the connection.

```json
{"type":"error","error":"badMessage","message":"expected one JSON object with a \"type\" per line"}
```

## 10. State reference

```json
{"type":"state","seq":35,"simTimeS":4.283,
 "control":{"authority":"pcc","holder":"PCC Lille","silenceS":0.1,"you":true},
 "line":{"id":"test-track","loop":false},
 "motion":{"positionM":2.637,"speedMS":2.183,"accelerationMS2":0.91,"sense":"AV"},
 "cab":{"kg":true,"kibs":false,"kph":false,"pa":true,"nav":false,"reverser":"AV","masterController":0},
 "drive":{"paActive":true,"demand":0.7},
 "voyants":{"trac":true,"frein":false,"hm":false,"pm":false,"pa":true,"port":false,"urg":false},
 "doors":{"left":0,"right":0,"canOperate":false},
 "vigilance":{"timerS":0,"warning":false},
 "emergencyBrake":{"applied":false},
 "pa":{"target":0,"dwellRemainingS":0},
 "station":{"next":0,"nextDistanceM":247.36},
 "telemetry":{"traction":{"lineVoltageV":743.9,"lineCurrentA":305.6,"armatureCurrentA":544.1,"fieldCurrentA":32.1,"chopperDuty":0.281,"tractionCurrentA":1088.2,"torquePct":100,"regenerating":false,"fieldWeakened":false},
              "auxiliaries":{"converterV":111.9,"batteryV":76.5,"lightingA":15,"compressor":false,"mainReservoirBar":8.43,"brakeBoxC":30}}}
```

| Field | Type | Meaning |
|-------|------|---------|
| `seq` | integer | This session's state counter, from 1. A gap means the cab skipped samples because the client wasn't reading fast enough. |
| `simTimeS` | number | Simulated time since the cab started (s). |
| **`control`** | | |
| `authority` | `"local"` / `"pcc"` | The COMMANDE selector. |
| `holder` | string? | Name of the session holding control; absent when nobody does. |
| `you` | boolean | This session holds control. |
| `silenceS` | number | Watchdog: seconds since the controller was last heard. Runs under PCC command only; past `link.timeoutS` the emergency brake latches. |
| **`line`** | | The line the rame is on. Its full description comes in `hello` and the `line` event. |
| `id` | string | `test-track`, or the id of the PCC's line. |
| `loop` | boolean | The line is a loop. |
| **`motion`** | | |
| `positionM` | number | Position on the line (§6.2), 0 … `lengthM` (below `lengthM` on a loop). |
| `speedMS` | number | Speed (≥ 0). |
| `accelerationMS2` | number | Rate of change of speed over the last step (negative while slowing). |
| `sense` | `"AV"` / `"AR"` | The sense the train runs in: AV towards higher positions, AR towards lower. It follows the reverser; at 0 the simulator runs in the AV sense. |
| **`cab`** | | The pupitre's controls, as set — by the PCC or the cab's operator. |
| `kg`, `kibs`, `kph` | boolean | The K switches. |
| `pa` | boolean | The PA selector. |
| `nav` | boolean | NAV shuttle. |
| `reverser` | `"AV"` / `"0"` / `"AR"` | Reverser position. |
| `masterController` | number | T/F lever, −1…+1. |
| **`drive`** | | |
| `paActive` | boolean | PA is actually driving: selected, KG on, reverser out of 0, emergency brake released, doors closed. |
| `demand` | number | The traction/brake demand that acted on the last step, −1…+1: PA's own command while PA drives, otherwise the lever. |
| **`voyants`** | | The pupitre's indicator lights. |
| `trac` | boolean | Traction commanded. |
| `frein` | boolean | Braking (service or emergency). |
| `hm` | boolean | Dead-man: KACOP held at the cab, or vigilance warning. |
| `pm` | boolean | Manual driving (KG on, reverser out of 0, PA off). |
| `pa` | boolean | PA selected with KG on. |
| `port` | boolean | At least one door open. |
| `urg` | boolean | Emergency brake latched. |
| **`doors`** | | |
| `left`, `right` | number | Openness of each side, 0 (closed) … 1 (open). |
| `canOperate` | boolean | The door interlock is satisfied (§8). |
| **`vigilance`** | | |
| `timerS` | number | Dead-man timer: seconds of manual running since the last KACOP. |
| `warning` | boolean | Past `limits.deadmanWarnS`: acknowledge with `kacop`. |
| **`emergencyBrake`** | | |
| `applied` | boolean | The emergency brake is latched. |
| `cause` | string? | Who latched it: `cab` (ARRÊT at the cab), `pcc` (a PCC command), `deadman` (vigilance timeout), `pccLink` (watchdog), `limit` (ran past the stopping point). Absent while released. |
| **`limit`** | | The PCC's stopping point (§6.3). Absent when there is none. |
| `positionM` | number | Where it is. |
| `distanceM` | number | How far ahead it lies in the running sense; negative once past it. |
| **`pa`** | | PA station sequencing. |
| `target` | integer? | Station PA is driving to. |
| `berthed` | integer? | Station PA is berthed at. |
| `dwellRemainingS` | number | Dwell left before PA departs (0 when not berthed). |
| **`station`** | | |
| `current` | integer? | Station whose stopping box (±`stationToleranceM`) contains the train. |
| `next` | integer? | Next station more than 1 m ahead in the running sense; absent past the last one (never on a loop). |
| `nextDistanceM` | number? | Distance to it. |
| **`telemetry`** | | The rame's instruments, derived each step from what the simulation is doing (§10.1). |
| `traction.lineVoltageV` | number | Voltage at the collector shoes: 750 V, sagging under traction, rising (to 825 V at most) while regenerating. |
| `traction.lineCurrentA` | number | Chopper input current, both cars (IL); negative while regenerating. |
| `traction.armatureCurrentA` | number | Armature loop current per car (II), 620 A at most. |
| `traction.fieldCurrentA` | number | Field current per motor (IEX): 0.059 × II, or 0.034 × II with the field weakened. |
| `traction.chopperDuty` | number | Chopper modulation ratio (MHI), 0…1. |
| `traction.tractionCurrentA` | number | Armature current of both cars. |
| `traction.torquePct` | number | Rim force against full traction effort, −100…+100; braking negative, friction included. |
| `traction.regenerating` | boolean | The service brake is returning energy to the line. |
| `traction.fieldWeakened` | boolean | The motors run on the weakened field (high speed). |
| `auxiliaries.converterV` | number | Static converter (low-voltage bus), ~112 V while KG is on. |
| `auxiliaries.batteryV` | number | Battery, floating at 76.5 V on the converter. |
| `auxiliaries.lightingA` | number | Lighting load: 15 A, +2 A with KPH. |
| `auxiliaries.compressor` | boolean | The compressor is running. |
| `auxiliaries.mainReservoirBar` | number | Main reservoir pressure; the compressor holds it between 7.4 and 9.0 bar. |
| `auxiliaries.brakeBoxC` | number | Brake-box temperature (°C), warmed by friction braking. |

### 10.1 The telemetry model

The figures follow the VAL 206 traction chain — per car, a chopper feeding
two series DC motors through an 8.6 reduction to 0.445 m tyres, for a 31 t
rame — with the same constants as metroSystem's VAL backend, so a cab's rame
and metroSystem's own read alike:

- **Traction.** The rim force the lever (or PA) asks for gives the armature
  current; the field current follows it at 0.059 × II until the armature loop
  needs more than the line voltage, then at 0.034 × II; the chopper duty is
  the loop voltage over 750 V, and IL = 2 · MHI · II.
- **Braking.** The service brake regenerates above 1.5 m/s (85 % of the
  current reaches the line) and is friction below. The emergency brake is
  friction only.
- **Auxiliaries.** Behind KG: with KG off the converter, the compressor and
  the lighting drop out and the battery slowly sags. Friction braking draws
  on the main reservoir and heats the brake box.

The telemetry feeds nothing back into the physics.

## 11. Events reference

| `event` | Fields | When |
|---------|--------|------|
| `authority` | `authority` | The COMMANDE selector moved. |
| `control` | `holder`?, `you`, `reason` | Control changed hands. `reason`: `acquired`, `preempted`, `released`, `timeout` (holder silent 3 s), `disconnected`. `holder` is absent when nobody holds control. |
| `line` | `line` | The rame changed line: the full description of the line it is on now, as in `hello`. |
| `emergencyBrake` | `applied`, `cause`? | The emergency brake latched (with its cause) or was released. |
| `vigilance` | `warning` | The dead-man warning came on or went off. |
| `paBerth` | `station`, `berthed` | PA berthed at `station` (`true`), or that berth ended (`false`) — a departure, or PA's sequence reset by PA off, KG off, the reverser to 0 or a change of line. |
| `doors` | `open` | The PORT voyant came on or went off. |
| `cab` | `rame` | The cab's operator renumbered the rame. |

## 12. Error codes

| Code | Sent as | Meaning |
|------|---------|---------|
| `badMessage` | `error` | The line isn't a JSON object with a string `type`, or a field has the wrong JSON type. |
| `unknownType` | `result` | Unrecognised message `type`. |
| `unsupportedProtocol` | `result`, then disconnection | `hello.protocol` isn't 1. |
| `unknownCommand` | `result` | Unrecognised `command`. |
| `badValue` | `result` | The `value` doesn't fit the command, or a `line` or `traffic` message doesn't fit; `message` says what. |
| `localAuthority` | `result` | The cab is under LOCALE command. |
| `notController` | `result` (+ `holder`) | This session doesn't hold control. |
| `controlHeld` | `result` (+ `holder`) | Another session holds control; use `force` to preempt. |
| `notStopped` | `result` | The reverser only moves, and the rame only joins a line, at a stand. |
| `doorsInterlocked` | `result` | Doors only work with KG on, stopped, at a platform. |
| `tooManySessions` | `error`, then disconnection | The cab already has 8 sessions. |
| `lineTooLong` | `error`, then disconnection | A line exceeded 64 KiB. |

## 13. Operating recipes

**Take over a cab.** Connect, send `hello`, then `acquire`, and start pinging
every second. If `state.emergencyBrake.cause` is `pccLink`, the cab was waiting
for a PCC: release it with `emergencyBrake false` once you're ready.

**Put the rame on your line.** Once `state.control.authority` is `pcc` and the
rame stands still, send your `line` with the position to join at — a station
clear of your other trains. Watch for the `line` event or `state.line.id`.

**Put the rame in automatic service.**

```json
{"type":"command","id":10,"command":"kg","value":true}
{"type":"command","id":11,"command":"reverser","value":"AV"}
{"type":"command","id":12,"command":"pa","value":true}
{"type":"command","id":13,"command":"nav","value":true}
```

PA then runs station to station: it berths within a few centimetres of each
mark and holds a 10 s dwell (`paBerth` events). On a straight line, NAV turns
it back at each terminus by itself; a loop has no terminus.

**Protect it.** Send `limit` with the point it must not pass whenever that
point changes — on a fixed-block line, a margin short of the first occupied
block ahead — and `limit` with no value when the way is clear. PA stops there;
the cab trips its emergency brake if it runs past.

**Show it the traffic.** Five times a second, send `traffic` with every other
rame on your line, converted to the cab's reference point (§6.2).

**Work the doors at a station.** When `state.doors.canOperate` is true, send
`doorsOpen` (`left`, `right` or `both`), then `doorsClose`. Under PA, closing
the doors after opening them ends the dwell, and the rame departs.

**Drive manually.** Send `pa false`, then set `masterController`, and send
`kacop` at least every 14 s while the train runs.

**Recover from a dead-man trip.** Send `kacop` first, then
`emergencyBrake false`. Released the other way round, the brake latches again
straight away, as long as the vigilance timer is still past its limit.

**Stop the train.** Send `emergencyBrake true` (any session can), or under
manual driving bring `masterController` to −1.

**Hand back.** Ask the cab's operator to turn the selector to LOCALE, then
`release`. Releasing while the cab is still under PCC command leaves it
without a controller, and the watchdog applies the emergency brake 3 s later.

## 14. Cab configuration

The cab's settings live in its user defaults. Each can also be given for one
run as a launch argument (`open -a VALPupitreSim --args -pccRame 302`).

| Key | Default | Meaning |
|-----|---------|---------|
| `pccAuthority` | `local` | The COMMANDE selector. Saved whenever it is moved at the cab. |
| `pccRame` | 301–399, derived from the cab id | Rame number shown to PCCs, up to 16 characters. Set it in the cab's **PCC** panel (click the PCC pill). |
| `pccPort` | `5206` | Preferred TCP port; `0` asks the OS for one. A taken port falls back to an OS-assigned one. |
| `pccLoopbackOnly` | `false` | Accept connections from this Mac only. |
| `pccCabID` | generated | The cab's identity. Generated on first launch; don't edit it. |

Run one cab per Mac. Two copies of the app on one Mac share their settings,
and therefore their identity.

## 15. Integrating with metroSystem

metroSystem is a complete PCC for this link. Its pupitre link
(`Sources/MetroSystem/Networking/PupitreLink.swift`, documented in its
`docs/pupitre-link.md`) runs every cab it finds on metroSystem's own loop,
alongside metroSystem's trains:

- **Discovery.** It browses `_valpupitre._tcp`, skips cabs with another
  `proto`, and keys each cab on its TXT `id`. Cabs it can't browse for can be
  added by address with `SET PUPITRE /ADD=(host,port)`.
- **Control.** Every metroSystem node sends a plain `acquire`. The node it
  succeeds for is the cab's single authority — the counterpart of
  metroSystem's `ownerPeerId` rule — and the others only monitor.
  `SET PUPITRE rame /RELEASE` gives a cab back; `/ACQUIRE /FORCE` takes one.
- **The line.** When a cab it controls is under PCC command and stands still,
  it lends it the loop — the id is derived from the layout, so it is the same
  on every node — at the station farthest from its trains. It then mirrors the
  cab into its world as rame `cab.rame`, owned by `pupitre:<cab id>`, so every
  metroSystem screen shows it and its wayside counts it as block occupancy.
- **Protection.** It gives the cab the stopping point its fixed-block wayside
  would give one of its own rames: 8 m short of the first occupied block or
  barred switch zone ahead, or where the rame can stop while line service is
  off. A general emergency stop applies every cab's emergency brake, and
  releases them when it ends.
- **Traffic.** Five times a second it sends each cab every other rame on the
  loop: its own trains, other nodes' and other cabs'.
- **Telemetry.** It asks for state 20 times a second and shows the cab's own
  instruments (`state.telemetry`) on its train-detail synoptic, DCL and
  Modbus, and lists cab rames first in its PCC window.
- **Geometry.** metroSystem places a rame by its head. It converts the cab's
  position with `hello.geometry` (§6.2), and converts back for stopping points
  and traffic.

**Commands.** metroSystem's `TrainCommandKind` → cab command:

| metroSystem | Cab | Note |
|-------------|-----|------|
| `openDoors` | `doorsOpen "both"` | metroSystem has no door side. |
| `closeDoors` | `doorsClose` | |
| `fuSet` | `emergencyBrake true` | |
| `fuRelease` | `emergencyBrake false` | The cab doesn't require a stand. |
| `modeAuto` | `pa true` | PA needs KG on and the reverser out of 0: metroSystem sends `kg true` and `reverser "AV"` first when they aren't. |
| `modeManual` | `pa false` | |
| `setSpeed` | — | The cab has no CML governor. |
| `pupitreKG` | `kg` | `value` 1/0 passes through. |
| `pupitreReverser` | `reverser` | `value` +1/0/−1 passes through. |
| `pupitreLever` | `masterController` | |
| `pupitreKIBS` | `kibs` | |
| `pupitreKPH` | `kph` | |
| `kacopAck` | `kacop` | metroSystem's `kacopAck` also releases a vigilance FU at a stand, so metroSystem follows it with `emergencyBrake false` when the cab stands with cause `deadman`. |
| `avpSelect`, `avpVoting` | — | The cab has no AVP strings. |

**State.** Cab state → `Train`:

| `Train` | From the cab |
|---------|--------------|
| `id` | `cab.id` (the TXT `id`) |
| `label` | `cab.rame` (watch for `cab` events) |
| `position` | The head: `motion.positionM` + `avEndM` running AV, − `arEndM` running AR (§6.2) |
| `speed`, `acceleration` | `motion.speedMS`, `motion.accelerationMS2` |
| `travelDirection` | `motion.sense`: `AV` → forward, `AR` → reverse |
| `mode` | `cab.pa`: true → auto, false → manual |
| `status` | `emergencyBrake.applied` → emergency; `pa.berthed` present or `voyants.port` → docked; `speedMS` > 0.05 → moving; otherwise stopped |
| `doorsOpen` | `voyants.port` |
| `isDwelling`, `dwellRemaining` | `pa.berthed` present, `pa.dwellRemainingS` |
| `nextStationName` | `line.stations[station.next].name` |
| `isEmergencyBrakeApplied` | `emergencyBrake.applied` |
| `ebCause` | `cab`, `pcc` → `operatorFU`; `deadman` → `vigilance`; `pccLink` → `controllerAlarm`; `limit` → `ppOverrun` |
| `pupitreKG`, `pupitreKIBS`, `pupitreKPH` | `cab.kg`, `cab.kibs`, `cab.kph` |
| `pupitreReverser` | `cab.reverser`: AV → +1, 0 → 0, AR → −1 |
| `pupitreLever` | `cab.masterController` |
| `kacopSecondsSinceAck`, `kacopWarning` | `vigilance.timerS`, `vigilance.warning` |
| `speedProgram`, `movementAuthority`, `distanceToMA`, `consigneVitesse` | The stopping point metroSystem gives the cab: the perturbed program while a rame ahead holds it, the normal one otherwise |
| `mainVoltage`, `lineCurrent`, `armatureCurrent`, `excitationCurrent`, `modulationRatio`, `tractionCurrent`, `tractionTorque` | `telemetry.traction`: `lineVoltageV`, `lineCurrentA`, `armatureCurrentA`, `fieldCurrentA`, `chopperDuty`, `tractionCurrentA`, `torquePct` |
| `cvsOutputVoltage`, `batteryVoltage`, `lightingCurrent`, `isCompressorRunning`, `compressorPressure`, `brakeBoxTemperature` | `telemetry.auxiliaries`: `converterV`, `batteryV`, `lightingA`, `compressor`, `mainReservoirBar`, `brakeBoxC` |

**Authority.** While `control.authority` is `local`, the cab refuses
everything but the emergency brake and runs on its own test track; metroSystem
takes its rame off the loop until it comes back.

## 16. Example session

A PCC takes over a cab that its operator has just switched to PCC. It
releases the emergency brake as part of taking over — a no-op here, because
the watchdog hadn't tripped yet — puts the rame on its loop, protects it,
shows it the traffic, puts it in automatic service, and then gets two
refusals. Lines marked `>` go from the PCC to the cab, `<` from the cab to the
PCC; long lines are abridged.

```
< {"type":"hello","app":"VALPupitreSim","appVersion":"1.0","authority":"pcc","cab":{"id":"929B91EB-…","name":"Rame 301 — Mac Studio","rame":"301"}, …}
< {"type":"state","cab":{"kg":false, …},"control":{"authority":"pcc","silenceS":0.9,"you":false},"line":{"id":"test-track","loop":false}, …,"seq":1}
> {"type":"hello","id":1,"protocol":1,"name":"PCC Lille","stateRateHz":10}
< {"type":"result","id":1,"ok":true}
> {"type":"acquire","id":2}
< {"type":"result","id":2,"ok":true}
< {"type":"event","event":"control","holder":"PCC Lille","reason":"acquired","you":true}
> {"type":"command","id":3,"command":"emergencyBrake","value":false}
< {"type":"result","id":3,"ok":true}
> {"type":"line","id":4,"positionM":850,"line":{"id":"metroSystem-e08ce6e163d76bd5","name":"MetroSystem VAL","lengthM":1000,"loop":true,"stations":[…],"blocks":[…]}}
< {"type":"result","id":4,"ok":true}
< {"type":"event","event":"line","line":{"blocks":[…],"id":"metroSystem-e08ce6e163d76bd5","lengthM":1000,"loop":true,"name":"MetroSystem VAL","stationToleranceM":6,"stations":[…]}}
> {"type":"command","id":5,"command":"limit","value":885.6}
< {"type":"result","id":5,"ok":true}
> {"type":"traffic","id":6,"trains":[{"rame":"101","positionM":43.6,"sense":"AV","speedMS":0},{"rame":"102","positionM":976.2,"sense":"AV","speedMS":0}]}
< {"type":"result","id":6,"ok":true}
> {"type":"command","id":7,"command":"kg","value":true}
< {"type":"result","id":7,"ok":true}
> {"type":"command","id":8,"command":"reverser","value":"AV"}
< {"type":"result","id":8,"ok":true}
> {"type":"command","id":9,"command":"pa","value":true}
< {"type":"result","id":9,"ok":true}
< {"type":"event","berthed":true,"event":"paBerth","station":5}
> {"type":"ping","id":10}
< {"type":"pong","id":10}
  … the 10 s dwell at 4 Cantons, with a ping every second …
< {"type":"event","berthed":false,"event":"paBerth","station":5}
< {"type":"state","cab":{"kg":true,…,"pa":true,"reverser":"AV"},"control":{"authority":"pcc","holder":"PCC Lille","silenceS":0.1,"you":true},"drive":{"demand":0.7,"paActive":true},"limit":{"distanceM":32.96,"positionM":885.6},"line":{"id":"metroSystem-e08ce6e163d76bd5","loop":true},"motion":{"accelerationMS2":0.91,"positionM":852.637,"sense":"AV","speedMS":2.183}, …,"seq":142}
> {"type":"command","id":21,"command":"doorsOpen","value":"left"}
< {"type":"result","error":"doorsInterlocked","id":21,"message":"doors only work stopped at a platform with KG on","ok":false}
> {"type":"command","id":22,"command":"reverser","value":"AR"}
< {"type":"result","error":"notStopped","id":22,"message":"the reverser only moves at a stand","ok":false}
```

Joining at 850 m puts the rame on the platform of 4 Cantons, so PA berths
there first. Rame 102 stands at 976.2 m, so its tail is at 956.6 m, in the
block from 900 m. A fixed-block PCC stops the cab's head 8 m short of that
block, at 892 m, which puts the cab's own reference point 6.4 m further back,
at 885.6 m: after the dwell, PA stops there rather than run on round the loop
to the station at 50 m.

To try the cab by hand, connect with `nc <host> 5206`, then paste request
lines. While you hold control, a `{"type":"ping"}` at least every second
keeps the watchdog quiet.

## 17. Versioning

The protocol version is `1`: the `proto` TXT key, `hello.protocol` from the
cab, and the `protocol` a client may declare in its own `hello`.

- **Additive changes** — new fields, events, messages, commands or error
  codes — keep the version. Clients must ignore what they don't recognise.
- **Breaking changes** — removing or redefining anything above — bump the
  version. A cab refuses a client `hello` that declares another version
  (`unsupportedProtocol`).
