//
//  SimulationModel.swift
//  VALPupitreSim
//

import Foundation
import Observation

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

    // MARK: Driver inputs
    /// Master controller (manipulateur de traction-freinage).
    /// -1 = full service brake, 0 = coast, +1 = full traction.
    var masterController: Double = 0
    var emergencyBrake: Bool = false

    // MARK: Cab switches (latching)
    var kg: Bool = false       // Coupure Générale — master power key
    var kibs: Bool = false     // Inhibition Boucle de Sécurité
    var kph: Bool = false      // PHares (headlights)
    var paMode: Bool = false   // Pilote Automatique
    var paShuttle: Bool = false // NAVette — PA turns back on its own at each terminus

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

    // MARK: PA station sequencing (not observed)
    /// Station PA is berthed at, nil while running between stations.
    @ObservationIgnored private var paBerthedStation: Int?
    /// Seconds left of the station dwell before PA departs.
    @ObservationIgnored private var paDwellRemaining: Double = 0
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
    @ObservationIgnored private var paTargetStation: Int?
    /// True once the doors have been opened during the current berth; closing
    /// them then ends the dwell at once (the guide's FP → departure sequence).
    @ObservationIgnored private var paDoorsServed: Bool = false

    // MARK: Stations
    let stationPositions: [Double] = [250, 750, 1250]
    let stationNames: [String] = ["QUATRE-CANTONS", "RÉPUBLIQUE", "GRAND-PLACE"]
    let stationTolerance: Double = 6

    // MARK: Constants
    let maxSpeedMS: Double = 22.2          // 80 km/h cap in manual mode
    let maxAcceleration: Double = 1.3      // m/s²
    let maxServiceBrake: Double = 1.4      // m/s²
    let emergencyBrakeRate: Double = 2.8   // m/s²
    let rollingResistance: Double = 0.12   // m/s²
    let trackLengthM: Double = 1500
    let deadmanWarnAt: Double = 14
    let deadmanLimit: Double = 20

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

    // MARK: Derived

    var speedKMH: Double { speedMS * 3.6 }

    var positionLabel: String {
        String(format: "P%03.0f / %03.0f", positionM / 10, trackLengthM / 10)
    }

    var currentStationIndex: Int? {
        for (i, s) in stationPositions.enumerated() where abs(positionM - s) < stationTolerance {
            return i
        }
        return nil
    }

    var currentStationName: String? {
        currentStationIndex.map { stationNames[$0] }
    }

    var nextStation: (name: String, distanceM: Double)? {
        let sign: Double = direction == .reverse ? -1 : 1
        let candidates = stationPositions.enumerated().filter {
            (sign * ($0.element - positionM)) > 1
        }
        guard let next = candidates.min(by: {
            abs($0.element - positionM) < abs($1.element - positionM)
        }) else { return nil }
        return (stationNames[next.offset], abs(next.element - positionM))
    }

    var doorsAreOpen: Bool {
        doorsLeftOpenness > 0.02 || doorsRightOpenness > 0.02
    }

    var canOperateDoors: Bool {
        kg && speedMS < 0.1 && currentStationIndex != nil
    }

    // MARK: Step

    func update(dt: Double) {
        let kacopEdge = kacop && !previousKacop
        previousKacop = kacop

        let edgeOpenLeft = doorOpenLeft && !previousDoorOpenLeft
        let edgeOpenRight = doorOpenRight && !previousDoorOpenRight
        let edgeClose = doorClose && !previousDoorClose
        previousDoorOpenLeft = doorOpenLeft
        previousDoorOpenRight = doorOpenRight
        previousDoorClose = doorClose

        if kacopEdge { deadmanTimer = 0 }

        // Advance the PA station sequence before asking the auto-driver for a
        // command, so arrival/departure is decided from this frame's state.
        updatePAStationSequence(dt: dt)

        // Choose the controller: in PA mode the auto-driver overrides the
        // user's master-controller value entirely.
        let effective = paActive ? computePAController() : masterController

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
                voyantTraction = false
                voyantFreinage = true
                voyantUrgence = true
            } else if effective > 0.02 && tractionAllowed {
                accel = maxAcceleration * effective
                voyantTraction = true
                voyantFreinage = false
                voyantUrgence = false
            } else if effective < -0.02 {
                accel = maxServiceBrake * effective
                voyantTraction = false
                voyantFreinage = true
                voyantUrgence = false
            } else {
                accel = speedMS > 0 ? -rollingResistance : 0
                voyantTraction = false
                voyantFreinage = false
                voyantUrgence = false
            }
            speedMS = max(0, min(maxSpeedMS, speedMS + accel * dt))
            advancePosition(dt: dt)

            voyantPM = direction != .neutral && !paMode
            voyantHomme = kacop || deadmanWarning
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

        let rate = dt / 0.9     // ~0.9 s open/close travel
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
            emergencyBrake = true
        }
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
        // so that station can be a stop target again after a reverser change.
        if let cleared = paClearedStation,
           abs(positionM - stationPositions[cleared]) > stationTolerance * 2 {
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
        let sign: Double = direction == .reverse ? -1 : 1
        return sign * (stationPositions[station] - positionM)
    }

    /// Nearest station ahead in the direction of travel, skipping `excluded`.
    /// `nil` means there is nothing left to serve this way — a terminus.
    private func stationAhead(excluding excluded: Int?) -> Int? {
        stationPositions.indices
            .filter { $0 != excluded && aheadDistance(to: $0) > 0.5 }
            .min { aheadDistance(to: $0) < aheadDistance(to: $1) }
    }

    // MARK: PA controller
    //
    // Constant-deceleration profile: accelerate up to `paCruiseMS`, coast,
    // then brake onto the mark of the latched target station. The brake is
    // commanded as the *fraction of the service brake that stops the train
    // there*, recomputed every frame, rather than a fixed notch held until
    // the train happens to stop — a fixed notch leaves it metres short.
    private func computePAController() -> Double {
        // Berthed, or nothing left to serve this way: hold the brake.
        guard paBerthedStation == nil, let target = paTargetStation else { return -1.0 }

        // On (or past) the mark: full brake to a standstill.
        let stopDist = aheadDistance(to: target)
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
        positionM = max(0, min(trackLengthM, positionM + speedMS * dt * sign))
    }
}
