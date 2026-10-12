//
//  SimulationModel.swift
//  VALPupitreSim
//

import Foundation
import Observation

/// A line the rame runs on: the cab's own straight test track, or the line a
/// PCC lends it under PCC command (`SimulationModel.joinLine(_:at:)`), which
/// may be a loop.
nonisolated struct TrackLayout: Equatable {
    struct Station: Equatable {
        var name: String
        var positionM: Double
    }

    /// A fixed block (canton) of the line, for display.
    struct Block: Equatable {
        var id: Int
        var startM: Double
        var lengthM: Double
    }

    /// `test-track` for the cab's own track, the PCC's identifier otherwise.
    var id: String
    var name: String
    var lengthM: Double
    var isLoop: Bool
    /// Ordered by position along the line.
    var stations: [Station]
    var blocks: [Block] = []

    var isTestTrack: Bool { id == Self.testTrack.id }

    /// The cab's own 1.5 km straight test track.
    static let testTrack = TrackLayout(
        id: "test-track", name: "VOIE D'ESSAI", lengthM: 1500, isLoop: false,
        stations: [Station(name: "QUATRE-CANTONS", positionM: 250),
                   Station(name: "RÉPUBLIQUE", positionM: 750),
                   Station(name: "GRAND-PLACE", positionM: 1250)])
}

/// Another rame on the PCC's line, as the PCC reports it (`traffic`).
struct OtherRame: Equatable {
    /// Its number, shown on the 3D views.
    var rame: String
    /// Measured as this rame's own `positionM` is: the centre of car 1.
    var positionM: Double
    var speedMS: Double
    /// `.forward` (AV, towards higher positions) or `.reverse` (AR).
    var sense: SimulationModel.Direction
}

/// Observable state for the VAL 206 manual-driving simulator.
///
/// Naming follows the actual cab labels used on VAL rolling stock and discussed
/// in the pupitre build log (KG, KACOP, KIBS, KPH, etc.). Speeds are stored in
/// m/s internally; the speedometer presents km/h.
@Observable
final class SimulationModel {

    // MARK: Train state
    var speedMS: Double = 0
    var positionM: Double = 0
    var direction: Direction = .neutral

    // MARK: Line
    /// The line the rame is on: the test track, or a PCC's line under PCC
    /// command. Change it with `joinLine(_:at:)`; handing the cab back to
    /// LOCALE returns the rame to the test track.
    private(set) var layout: TrackLayout = .testTrack
    /// Where the rame stood on the test track before it joined a PCC's line,
    /// so it can be put back there.
    @ObservationIgnored private var testTrackPosition: Double = 0
    /// Stopping point (point d'arrêt) the PCC imposes on its line: PA stops
    /// at it, and running past it trips the emergency brake.
    var stopLimitM: Double?
    /// The other rames on the line, as the PCC last reported them, carried
    /// forward at their own speed between reports. Display only: keeping
    /// clear of them is the PCC's business, through its stopping point.
    private(set) var otherRames: [OtherRame] = []
    /// Seconds since the PCC's last traffic report.
    @ObservationIgnored private var trafficAge: Double = 0

    // MARK: Driver inputs
    /// Master controller (manipulateur de traction-freinage).
    /// -1 = full service brake, 0 = coast, +1 = full traction.
    var masterController: Double = 0
    /// Latched emergency brake (ARRÊT). Whoever latched it is recorded in
    /// `emergencyBrakeCause`; a plain set — the on-screen or HID ARRÊT —
    /// counts as the cab's own.
    var emergencyBrake: Bool = false {
        didSet {
            if !emergencyBrake {
                emergencyBrakeCause = nil
            } else if emergencyBrakeCause == nil {
                emergencyBrakeCause = .cab
            }
        }
    }
    /// Why the emergency brake is latched; nil while it is released.
    private(set) var emergencyBrakeCause: EmergencyCause?

    // MARK: Cab switches (latching)
    var kg: Bool = false       // Coupure Générale — master power key
    var kibs: Bool = false     // Inhibition Boucle de Sécurité
    var kph: Bool = false      // PHares (headlights)
    var paMode: Bool = false   // Pilote Automatique
    var paShuttle: Bool = false // NAVette — PA turns back on its own at each terminus

    // MARK: Command authority — the local pupitre or the PCC
    /// Who commands the cab, chosen at the cab only (the COMMANDE selector).
    /// Under `.pcc` the pupitre and HID inputs are locked out except ARRÊT,
    /// commands arrive over the PCC link (`PCCLink`), and the link watchdog
    /// in `update(dt:)` holds the train whenever no PCC is live.
    var authority: CommandAuthority = .local {
        didSet {
            guard authority != oldValue else { return }
            // Handing over to the PCC opens a fresh watchdog window, so a
            // PCC that is already connected never sees a spurious trip.
            pccLinkSilence = 0
            if authority == .pcc {
                // The pupitre goes dead: let go of any momentary button still
                // held, since its release would no longer get through.
                kacop = false
                hornPressed = false
                doorOpenLeft = false
                doorOpenRight = false
                doorClose = false
            } else {
                // A PCC's line is lent for PCC command only, and so are its
                // stopping point and the picture of its traffic — the PCC
                // couldn't lift them under LOCALE.
                leaveLine()
                stopLimitM = nil
                clearTraffic()
            }
        }
    }

    // MARK: KACOP — momentary dead-man acknowledgment (true while held)
    var kacop: Bool = false

    // MARK: Push buttons (momentary)
    var hornPressed: Bool = false
    var doorOpenLeft: Bool = false
    var doorOpenRight: Bool = false
    var doorClose: Bool = false

    // MARK: Voyants
    var voyantTraction: Bool = false
    var voyantFreinage: Bool = false
    var voyantHomme: Bool = false       // Veille acknowledged / dead-man alert
    var voyantPM: Bool = false          // Pilotage Manuel active
    var voyantUrgence: Bool = false
    var voyantPA: Bool { paMode && kg } // Pilotage Automatique selected
    var voyantPort: Bool {              // Door open indicator
        doorsLeftOpenness > 0.02 || doorsRightOpenness > 0.02
    }

    /// PA is *actively* driving (not just selected) when power is up, a
    /// direction is chosen, and nothing has inhibited motion.
    var paActive: Bool {
        paMode && kg && direction != .neutral && !emergencyBrake && !doorsAreOpen
    }

    // MARK: Doors
    @ObservationIgnored private var doorsLeftTarget: Bool = false
    @ObservationIgnored private var doorsRightTarget: Bool = false
    var doorsLeftOpenness: Double = 0
    var doorsRightOpenness: Double = 0

    // MARK: Dead-man
    var deadmanTimer: Double = 0
    var deadmanWarning: Bool { deadmanTimer > deadmanWarnAt }
    var deadmanFraction: Double { min(1, deadmanTimer / deadmanLimit) }

    // MARK: Edge-detection state (not observed)
    @ObservationIgnored private var previousKacop: Bool = false
    @ObservationIgnored private var previousDoorOpenLeft: Bool = false
    @ObservationIgnored private var previousDoorOpenRight: Bool = false
    @ObservationIgnored private var previousDoorClose: Bool = false

    // MARK: Remote presses (not observed)
    /// One-shot presses injected by the PCC link, consumed by the next
    /// `update(dt:)` as rising edges. They never touch the level inputs
    /// above, so a remote press can't leave a button looking held down.
    @ObservationIgnored private var pendingKacopPress: Bool = false
    @ObservationIgnored private var pendingDoorOpenLeftPress: Bool = false
    @ObservationIgnored private var pendingDoorOpenRightPress: Bool = false
    @ObservationIgnored private var pendingDoorClosePress: Bool = false

    // MARK: PCC link watchdog (not observed)
    /// Seconds since the controlling PCC was last heard. Runs only under
    /// PCC command; `pccHeartbeat()` resets it.
    @ObservationIgnored private(set) var pccLinkSilence: Double = 0

    // MARK: Telemetry (not observed — read by the PCC link)
    /// Simulated seconds since launch.
    @ObservationIgnored private(set) var simTime: Double = 0
    /// Rate of change of speed over the last step (m/s²).
    @ObservationIgnored private(set) var accelerationMS2: Double = 0
    /// Controller value that acted on the last step: PA's command in PA,
    /// otherwise the master controller.
    @ObservationIgnored private(set) var effectiveController: Double = 0
    /// The rame's instruments — traction chain and auxiliaries — as of the
    /// last step. Derived only; nothing in the physics reads it.
    @ObservationIgnored private(set) var telemetry = RameTelemetry()

    // MARK: PA station sequencing (not observed)
    /// Station PA is berthed at, nil while running between stations.
    @ObservationIgnored private(set) var paBerthedStation: Int?
    /// Seconds left of the station dwell before PA departs.
    @ObservationIgnored private(set) var paDwellRemaining: Double = 0
    /// Station PA has already served. Excluded as a stop target so the train
    /// leaves instead of re-braking onto the platform it is standing at.
    @ObservationIgnored private var paClearedStation: Int?
    /// True once PA has begun braking onto the mark. Latched, with a wide
    /// release band, so the stop profile cannot chatter in and out of the
    /// brake band frame by frame.
    @ObservationIgnored private var paBraking: Bool = false
    /// Station PA is currently driving to. Latched for the whole run so that
    /// creeping a few centimetres past the mark cannot make PA give up on the
    /// platform and set off for the next one.
    @ObservationIgnored private(set) var paTargetStation: Int?
    /// True once the doors have been opened during the current berth; closing
    /// them then ends the dwell at once (the guide's FP → departure sequence).
    @ObservationIgnored private var paDoorsServed: Bool = false

    // MARK: Stations (of the current line)
    var stationPositions: [Double] { layout.stations.map(\.positionM) }
    var stationNames: [String] { layout.stations.map(\.name) }
    let stationTolerance: Double = 6

    // MARK: Constants
    let maxSpeedMS: Double = 22.2          // 80 km/h cap in manual mode
    let maxAcceleration: Double = 1.3      // m/s²
    let maxServiceBrake: Double = 1.4      // m/s²
    let emergencyBrakeRate: Double = 2.8   // m/s²
    let rollingResistance: Double = 0.12   // m/s²
    var trackLengthM: Double { layout.lengthM }
    /// On a loop, a point up to this far behind the rame counts as just
    /// passed; anything further back lies ahead, a lap away.
    let loopBehindWindow: Double = 50
    /// How far past the PCC's stopping point the rame may roll before the
    /// emergency brake trips.
    let stopLimitOverrun: Double = 1
    let deadmanWarnAt: Double = 14
    let deadmanLimit: Double = 20
    let doorTravelTime: Double = 0.9   // s, fully closed ↔ fully open
    /// Silence from the controlling PCC, under PCC command, after which the
    /// emergency brake latches.
    let pccLinkTimeout: Double = 3
    /// Age past which the PCC's traffic report is stale and the other rames
    /// are taken off the views.
    let trafficTimeout: Double = 2

    // Rame geometry: two 12.8 m cars, centres 13.2 m apart. `positionM` is
    // the centre of car 1, the car at the AV end, so the rame reaches 6.4 m
    // beyond it towards AV and 19.6 m back towards AR — 26 m in all.
    static let carLengthM: Double = 12.8
    static let carPitchM: Double = 13.2
    static var avEndM: Double { carLengthM / 2 }
    static var arEndM: Double { carPitchM + carLengthM / 2 }

    // PA profile
    let paCruiseMS: Double = 16.7      // ~60 km/h
    let paBrakeRate: Double = 1.0      // deceleration the stop profile aims for (m/s²)
    let paStopTolerance: Double = 0.05 // "on the mark" band around the platform centre
    let paDwellTime: Double = 10       // station dwell before PA departs on its own

    // MARK: Callbacks (set by ContentView to drive audio events)
    @ObservationIgnored var onDoorChime: (() -> Void)?

    enum Direction: String, CaseIterable, Hashable {
        case forward = "AV"
        case neutral = "0"
        case reverse = "AR"
    }

    enum CommandAuthority: String, CaseIterable, Hashable {
        case local      // commande locale — the pupitre drives
        case pcc        // commande PCC — the PCC drives over the network
    }

    enum EmergencyCause: String, Hashable {
        case cab        // ARRÊT on the pupitre (on-screen or HID)
        case pcc        // commanded over the PCC link
        case deadman    // KACOP vigilance timeout
        case pccLink    // no live PCC while under PCC command
        case limit      // ran past the PCC's stopping point
    }

    // MARK: Derived

    var speedKMH: Double { speedMS * 3.6 }

    var positionLabel: String {
        String(format: "P%03.0f / %03.0f", positionM / 10, trackLengthM / 10)
    }

    var currentStationIndex: Int? {
        for (i, s) in stationPositions.enumerated()
        where trackDistance(positionM, s) < stationTolerance {
            return i
        }
        return nil
    }

    var currentStationName: String? {
        currentStationIndex.map { stationNames[$0] }
    }

    var nextStation: (name: String, distanceM: Double)? {
        nextStationAhead.map { (stationNames[$0.index], $0.distanceM) }
    }

    /// The next station more than a metre ahead in the direction of travel.
    var nextStationAhead: (index: Int, distanceM: Double)? {
        let ahead = stationPositions.indices
            .map { (index: $0, distanceM: aheadDistance(toPosition: stationPositions[$0])) }
            .filter { $0.distanceM > 1 }
        return ahead.min { $0.distanceM < $1.distanceM }
    }

    /// Distance from the rame to `target` along its running direction:
    /// positive ahead, negative behind. On a loop everything lies ahead,
    /// except the last `loopBehindWindow` metres, which count as just passed.
    func aheadDistance(toPosition target: Double) -> Double {
        let sign: Double = direction == .reverse ? -1 : 1
        let d = sign * (target - positionM)
        guard layout.isLoop else { return d }
        let lap = layout.lengthM
        var ahead = d.truncatingRemainder(dividingBy: lap)
        if ahead < 0 { ahead += lap }
        return ahead > lap - loopBehindWindow ? ahead - lap : ahead
    }

    /// Distance between two points of the line — the short way round on a
    /// loop.
    func trackDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return layout.isLoop ? min(d, layout.lengthM - d) : d
    }

    /// Distance to the PCC's stopping point along the running direction
    /// (negative once past it), or nil when there is none.
    var stopLimitDistance: Double? {
        stopLimitM.map { aheadDistance(toPosition: $0) }
    }

    /// The sense the train runs in along the track: towards higher positions
    /// (AV) unless the reverser is at AR — exactly how `advancePosition`
    /// moves it, the neutral reverser included.
    var runningSense: Direction { direction == .reverse ? .reverse : .forward }

    var doorsAreOpen: Bool {
        doorsLeftOpenness > 0.02 || doorsRightOpenness > 0.02
    }

    var canOperateDoors: Bool {
        kg && speedMS < 0.1 && currentStationIndex != nil
    }

    // MARK: Step

    func update(dt: Double) {
        let kacopEdge = (kacop && !previousKacop) || pendingKacopPress
        previousKacop = kacop

        let edgeOpenLeft = (doorOpenLeft && !previousDoorOpenLeft) || pendingDoorOpenLeftPress
        let edgeOpenRight = (doorOpenRight && !previousDoorOpenRight) || pendingDoorOpenRightPress
        let edgeClose = (doorClose && !previousDoorClose) || pendingDoorClosePress
        previousDoorOpenLeft = doorOpenLeft
        previousDoorOpenRight = doorOpenRight
        previousDoorClose = doorClose

        pendingKacopPress = false
        pendingDoorOpenLeftPress = false
        pendingDoorOpenRightPress = false
        pendingDoorClosePress = false

        if kacopEdge { deadmanTimer = 0 }

        // PCC link watchdog: under PCC command the cab needs a live PCC.
        // Silence beyond the timeout — link lost, PCC gone quiet, or no PCC
        // at all — latches the emergency brake: fail-safe by absence.
        if authority == .pcc {
            pccLinkSilence += dt
            if pccLinkSilence > pccLinkTimeout { applyEmergencyBrake(.pccLink) }
        } else {
            pccLinkSilence = 0
        }

        let speedBefore = speedMS

        // Advance the PA station sequence before asking the auto-driver for a
        // command, so arrival/departure is decided from this frame's state.
        updatePAStationSequence(dt: dt)

        // Choose the controller: in PA mode the auto-driver overrides the
        // user's master-controller value entirely.
        let effective = paActive ? computePAController() : masterController
        var regime: RameTelemetry.Regime = .off
        var commandedAccel: Double = 0

        if !kg {
            speedMS = max(0, speedMS - rollingResistance * 0.4 * dt)
            advancePosition(dt: dt)
            voyantTraction = false
            voyantFreinage = false
            voyantPM = false
            voyantHomme = false
            voyantUrgence = emergencyBrake
        } else {
            let tractionAllowed = !doorsAreOpen && direction != .neutral && !emergencyBrake
            var accel: Double = 0
            if emergencyBrake {
                accel = -emergencyBrakeRate
                regime = .emergency
                voyantTraction = false
                voyantFreinage = true
                voyantUrgence = true
            } else if effective > 0.02 && tractionAllowed {
                accel = maxAcceleration * effective
                regime = .motoring
                voyantTraction = true
                voyantFreinage = false
                voyantUrgence = false
            } else if effective < -0.02 {
                accel = maxServiceBrake * effective
                regime = .braking
                voyantTraction = false
                voyantFreinage = true
                voyantUrgence = false
            } else {
                accel = speedMS > 0 ? -rollingResistance : 0
                regime = .coast
                voyantTraction = false
                voyantFreinage = false
                voyantUrgence = false
            }
            commandedAccel = accel
            speedMS = max(0, min(maxSpeedMS, speedMS + accel * dt))
            advancePosition(dt: dt)

            voyantPM = direction != .neutral && !paMode
            voyantHomme = kacop || deadmanWarning
        }

        accelerationMS2 = dt > 0 ? (speedMS - speedBefore) / dt : 0
        effectiveController = effective
        simTime += dt
        advanceTraffic(dt: dt)
        telemetry.advance(dt: dt, regime: regime, accelMS2: commandedAccel, speedMS: speedMS,
                          rollingResistance: rollingResistance, headlights: kph)

        // The PCC's stopping point (point d'arrêt): rolling past it trips the
        // emergency brake, as the AVP does at the end of a perturbed program.
        if let limit = stopLimitDistance, limit < -stopLimitOverrun, speedMS > 0.3 {
            applyEmergencyBrake(.limit)
        }

        // Door interlock: only operate at a stopped station, force-close if moving
        if canOperateDoors {
            if edgeOpenLeft && !doorsLeftTarget {
                doorsLeftTarget = true
                onDoorChime?()
            }
            if edgeOpenRight && !doorsRightTarget {
                doorsRightTarget = true
                onDoorChime?()
            }
            if edgeClose {
                if doorsLeftTarget || doorsRightTarget { onDoorChime?() }
                doorsLeftTarget = false
                doorsRightTarget = false
            }
        } else if speedMS > 0.3 {
            doorsLeftTarget = false
            doorsRightTarget = false
        }

        let rate = dt / doorTravelTime
        doorsLeftOpenness = clamp01(doorsLeftOpenness + (doorsLeftTarget ? rate : -rate))
        doorsRightOpenness = clamp01(doorsRightOpenness + (doorsRightTarget ? rate : -rate))

        // Dead-man: count while train is running under manual control. PA
        // mode bypasses the vigilance device by design (it's an automatic
        // metro after all).
        let running = kg && direction != .neutral && speedMS > 0.5 && !paActive
        if running {
            deadmanTimer += dt
        } else {
            deadmanTimer = max(0, deadmanTimer - dt * 2)
        }
        if deadmanTimer > deadmanLimit {
            applyEmergencyBrake(.deadman)
        }
    }

    // MARK: Inputs from outside the pupitre

    /// Latch the emergency brake on behalf of `cause`. A brake that is
    /// already latched keeps the cause that applied it first.
    func applyEmergencyBrake(_ cause: EmergencyCause) {
        guard !emergencyBrake else { return }
        emergencyBrakeCause = cause
        emergencyBrake = true
    }

    /// A KACOP acknowledgment from the PCC: one rising edge, next step.
    func pressKacop() { pendingKacopPress = true }

    /// PO G and/or PO D pressed once from the PCC. The door interlock in
    /// `update(dt:)` applies exactly as to the pupitre buttons.
    func pressDoorOpen(left: Bool, right: Bool) {
        if left { pendingDoorOpenLeftPress = true }
        if right { pendingDoorOpenRightPress = true }
    }

    /// FP pressed once from the PCC.
    func pressDoorClose() { pendingDoorClosePress = true }

    /// The controlling PCC was heard: restart the link watchdog window.
    func pccHeartbeat() { pccLinkSilence = 0 }

    /// The PCC's report of the other rames on the line: it replaces the
    /// last one, and stands for `trafficTimeout` unless renewed.
    func setTraffic(_ rames: [OtherRame]) {
        otherRames = rames
        trafficAge = 0
    }

    /// Take the other rames off the views — the PCC that reported them is
    /// no longer the one in charge.
    func clearTraffic() {
        if !otherRames.isEmpty { otherRames = [] }
    }

    /// Carry the other rames forward at their reported speed until the next
    /// report, so they glide between reports instead of jumping; drop them
    /// once the report has gone stale.
    private func advanceTraffic(dt: Double) {
        guard !otherRames.isEmpty else { return }
        trafficAge += dt
        if trafficAge > trafficTimeout {
            otherRames = []
        } else if otherRames.contains(where: { $0.speedMS > 0 }) {
            // Only when something moves: every write invalidates the views.
            otherRames = otherRames.map { rame in
                var moved = rame
                let sign: Double = rame.sense == .reverse ? -1 : 1
                moved.positionM = onLine(rame.positionM + rame.speedMS * dt * sign)
                return moved
            }
        }
    }

    // MARK: Line changes

    /// Put the rame on a PCC's line at `position`. The PCC link calls this
    /// under PCC command with the rame at a stand; the rame's place on the
    /// test track is kept for the way back.
    func joinLine(_ line: TrackLayout, at position: Double) {
        if layout.isTestTrack { testTrackPosition = positionM }
        relocate(onto: line, at: position)
    }

    /// Back to the test track, where the rame left it.
    private func leaveLine() {
        guard !layout.isTestTrack else { return }
        relocate(onto: .testTrack, at: testTrackPosition)
    }

    /// Set the rame down on `line`: at a stand, doors shut, with PA's station
    /// sequence and the PCC's stopping point cleared for the new line.
    private func relocate(onto line: TrackLayout, at position: Double) {
        layout = line
        positionM = onLine(position)
        speedMS = 0
        stopLimitM = nil
        clearTraffic()
        doorsLeftTarget = false
        doorsRightTarget = false
        doorsLeftOpenness = 0
        doorsRightOpenness = 0
        paBerthedStation = nil
        paDwellRemaining = 0
        paClearedStation = nil
        paDoorsServed = false
        setPATarget(nil)
    }

    // MARK: PA station sequence
    //
    // The auto-driver alone cannot leave a platform: once stopped it is still
    // within the stop zone of the station it just served, so it would command
    // the brake forever. This little state machine berths the train on
    // arrival, holds it for a dwell (cut short by a door cycle), then marks
    // the station served so `computePAController` targets the next one.
    private func updatePAStationSequence(dt: Double) {
        // Deselecting PA — or losing power, or going to neutral — drops the
        // sequence so a later re-engagement re-evaluates from where we are.
        // A mere suspension (doors open, EB latched) keeps the berth.
        guard paMode && kg && direction != .neutral else {
            paBerthedStation = nil
            paDwellRemaining = 0
            paClearedStation = nil
            paDoorsServed = false
            setPATarget(nil)
            return
        }

        if let berthed = paBerthedStation {
            setPATarget(nil)
            if doorsAreOpen {
                paDoorsServed = true            // dwell pauses while doors are out
            } else {
                if paDwellRemaining > 0 { paDwellRemaining -= dt }
                // The doors closing (FP) ends the dwell at once; otherwise it
                // simply runs out. Either way we only leave if there is
                // somewhere to go: at a terminus PA holds the platform until
                // the reverser sends it back down the line — which NAV does
                // by itself once the dwell is over.
                let readyToLeave = paDoorsServed || paDwellRemaining <= 0
                if readyToLeave, paShuttle, stationAhead(excluding: berthed) == nil {
                    turnBack()
                }
                if readyToLeave, let onward = stationAhead(excluding: berthed) {
                    paClearedStation = berthed
                    paBerthedStation = nil
                    paDwellRemaining = 0
                    paDoorsServed = false
                    setPATarget(onward)
                }
            }
            return
        }

        // Arrival: stopped inside the box of a station we have not served yet.
        if speedMS < 0.1, let here = currentStationIndex, here != paClearedStation {
            paBerthedStation = here
            paDwellRemaining = paDwellTime
            paDoorsServed = false
            setPATarget(nil)
            return
        }

        // Drop a latched target that has ended up behind us — a reverser
        // change, or a platform blown through after an EB release.
        if let target = paTargetStation,
           aheadDistance(to: target) < -stationTolerance {
            setPATarget(nil)
        }

        // Release the served-station lockout once well clear of the platform,
        // so that station can be a stop target again after a reverser change
        // (or, on a loop, a lap later).
        if let cleared = paClearedStation,
           abs(aheadDistance(to: cleared)) > stationTolerance * 2 {
            paClearedStation = nil
        }

        if paTargetStation == nil {
            setPATarget(stationAhead(excluding: paClearedStation))
        }

        // Nothing ahead at all (engaged past the last platform): PA brakes to
        // a stand, and under NAV then turns back towards the line.
        if paTargetStation == nil, paShuttle, speedMS < 0.1 {
            turnBack()
            setPATarget(stationAhead(excluding: paClearedStation))
        }
    }

    /// NAV turnback: throw the reverser to the opposite direction, exactly as
    /// the driver would at a terminus. The pupitre's reverser follows it.
    private func turnBack() {
        direction = direction == .forward ? .reverse : .forward
    }

    /// Point PA at a new stop (or at nothing), resetting the brake latch with
    /// it so the stop profile is re-entered from scratch for the new run.
    private func setPATarget(_ station: Int?) {
        guard paTargetStation != station else { return }
        paTargetStation = station
        paBraking = false
    }

    /// Distance from the train to a station, measured along the direction of
    /// travel: positive ahead, negative behind.
    private func aheadDistance(to station: Int) -> Double {
        aheadDistance(toPosition: stationPositions[station])
    }

    /// Nearest station ahead in the direction of travel, skipping `excluded`.
    /// `nil` means there is nothing left to serve this way — a terminus. A
    /// loop has none: there is always a station ahead.
    private func stationAhead(excluding excluded: Int?) -> Int? {
        stationPositions.indices
            .filter { $0 != excluded && aheadDistance(to: $0) > 0.5 }
            .min { aheadDistance(to: $0) < aheadDistance(to: $1) }
    }

    // MARK: PA controller
    //
    // Constant-deceleration profile: accelerate up to `paCruiseMS`, coast,
    // then brake onto the mark of the latched target station — or onto the
    // PCC's stopping point, when that comes first. The brake is commanded as
    // the *fraction of the service brake that stops the train there*,
    // recomputed every frame, rather than a fixed notch held until the train
    // happens to stop — a fixed notch leaves it metres short.
    private func computePAController() -> Double {
        // Berthed, or nothing left to serve this way: hold the brake.
        guard paBerthedStation == nil, let target = paTargetStation else { return -1.0 }

        // On (or past) the mark: full brake to a standstill.
        let stopDist = min(aheadDistance(to: target), stopLimitDistance ?? .infinity)
        if stopDist <= paStopTolerance { return -1.0 }

        // Deceleration that would bring the train to rest on the mark.
        let decelNeeded = speedMS * speedMS / (2 * stopDist)

        // Schmitt trigger on the stop profile: once braking, keep braking
        // until well below the profile again. A single threshold chatters,
        // because braking at exactly the rate the profile asks for holds
        // `decelNeeded` pinned to the trigger point.
        if paBraking {
            if decelNeeded < paBrakeRate * 0.5 { paBraking = false }
        } else if decelNeeded >= paBrakeRate {
            paBraking = true
        }

        if paBraking {
            return -min(1.0, decelNeeded / maxServiceBrake)
        } else if decelNeeded >= paBrakeRate * 0.5 {
            return 0                            // nearly on the profile: coast in
        } else if speedMS < paCruiseMS {
            return 0.7
        } else {
            return 0
        }
    }

    private func clamp01(_ v: Double) -> Double { max(0, min(1, v)) }

    private func advancePosition(dt: Double) {
        let sign: Double = direction == .reverse ? -1 : 1
        positionM = onLine(positionM + speedMS * dt * sign)
    }

    /// A position brought onto the current line: wrapped round a loop,
    /// held between the ends of a straight track.
    private func onLine(_ position: Double) -> Double {
        guard layout.isLoop else { return max(0, min(trackLengthM, position)) }
        let wrapped = position.truncatingRemainder(dividingBy: trackLengthM)
        return wrapped < 0 ? wrapped + trackLengthM : wrapped
    }
}
