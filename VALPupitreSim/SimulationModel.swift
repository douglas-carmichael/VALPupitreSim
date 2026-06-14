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
    let paBrakeRate: Double = 1.0      // gentle service brake (m/s²)
    let paStopMargin: Double = 5       // start braking this far before the stop
    let paStopTolerance: Double = 1.5

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

    // MARK: PA controller
    //
    // Constant-deceleration profile: accelerate up to `paCruiseMS`, coast,
    // then brake so the train stops within ±`paStopTolerance` m of the next
    // station ahead in the current direction (or the end of the line).
    private func computePAController() -> Double {
        let sign: Double = direction == .reverse ? -1 : 1
        let candidates = stationPositions.filter {
            sign * ($0 - positionM) > 0.5
        }
        let target: Double
        if let next = candidates.min(by: {
            abs($0 - positionM) < abs($1 - positionM)
        }) {
            target = next
        } else {
            target = sign > 0 ? trackLengthM - 1 : 1
        }
        let dist = abs(target - positionM)
        let brakeDist = speedMS * speedMS / (2 * paBrakeRate)

        if dist < paStopTolerance {
            return -1.0
        } else if brakeDist >= max(0, dist - paStopMargin) {
            return -0.7
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
