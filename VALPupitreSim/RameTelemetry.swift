//
//  RameTelemetry.swift
//  VALPupitreSim
//

import Foundation

/// What the rame's own instruments would read — the traction chain's
/// electrical quantities and the auxiliaries — derived every step from what
/// the simulation is doing. It feeds nothing back into the physics; the PCC
/// link streams it (`state.telemetry`) so a PCC shows real figures.
///
/// The traction chain is the VAL 206's (Verhille thesis, Ch. 1), with the
/// constants metroSystem's VAL backend uses: per car a chopper feeding two
/// series DC motors through an 8.6 reduction to 0.445 m tyres, field current
/// held at 0.059 × the armature current ("image série") until the armature
/// loop runs out of line voltage, then weakened to 0.034. Service braking is
/// regenerative down to 1.5 m/s and friction below; the emergency brake is
/// friction only.
nonisolated struct RameTelemetry: Equatable {
    // Traction chain (both cars together where it says so)
    var lineVoltageV: Double = Self.lineVoltage
    /// Chopper input current, both cars; negative while regenerating.
    var lineCurrentA: Double = 0
    /// Armature loop current, per car (II).
    var armatureCurrentA: Double = 0
    /// Field current, per motor (IEX).
    var fieldCurrentA: Double = 0
    /// Chopper modulation ratio, 0…1 (MHI).
    var chopperDuty: Double = 0
    /// Armature current of both cars.
    var tractionCurrentA: Double = 0
    /// Rim force against full traction effort, −100…+100: braking negative,
    /// friction included.
    var torquePct: Double = 0
    var regenerating = false
    var fieldWeakened = false

    // Auxiliaries
    var converterV: Double = 0
    var batteryV: Double = 76.5
    var compressorRunning = false
    var mainReservoirBar: Double = 8.5
    var brakeBoxC: Double = Self.ambientC
    var lightingA: Double = 0

    // MARK: Constants (VAL 206, as in metroSystem's Sim)

    static let tareMass: Double = 31_000          // kg, empty rame
    static let gearRatio: Double = 8.6            // differential 4.3 × reducer 2.0
    static let wheelRadius: Double = 0.445        // m
    static let fullField: Double = 0.059          // iex = 0.059 ii
    static let weakField: Double = 0.034          // iex = 0.034 ii (field weakening)
    static let torquePerAmp2: Double = 0.0326     // N·m/A²
    static let armatureResistance: Double = 0.16  // Ω, armature loop
    static let armatureCurrentMax: Double = 620   // A, chopper ceiling
    static let lineVoltage: Double = 750          // V DC
    static let regenMinSpeed: Double = 1.5        // m/s, friction only below
    static let regenReceptivity: Double = 0.85
    static let fullEffortN: Double = tareMass * 1.3
    static let ambientC: Double = 30
    /// Brake-box heat capacity: a full emergency stop from 80 km/h warms it
    /// by about 60 °C.
    static let brakeBoxJPerK: Double = 125_000
    static let brakeBoxCoolingS: Double = 600

    /// What drove the rame over the last step.
    enum Regime {
        case off          // KG open: no traction power
        case coast
        case motoring     // traction, `accelMS2` > 0
        case braking      // service brake, `accelMS2` < 0
        case emergency
    }

    /// Advance over `dt`: `accelMS2` is the acceleration the traction or
    /// brake commanded (before rolling resistance), `speedMS` the speed
    /// after the step.
    mutating func advance(dt: Double, regime: Regime, accelMS2: Double, speedMS v: Double,
                          rollingResistance: Double, headlights: Bool) {
        let mass = Self.tareMass
        var motoringForce = 0.0, electricBrakeForce = 0.0, frictionForce = 0.0
        switch regime {
        case .off, .coast:
            break
        case .motoring:
            // The chain also pulls against rolling resistance once moving.
            motoringForce = mass * (accelMS2 + (v > 0.1 ? rollingResistance : 0))
        case .braking:
            // At a stand the held brake does no work and draws no air.
            let force = v > 0.01 ? mass * max(0, -accelMS2 - (v > 0.1 ? rollingResistance : 0)) : 0
            if v > Self.regenMinSpeed { electricBrakeForce = force } else { frictionForce = force }
        case .emergency:
            frictionForce = v > 0.01 ? mass * max(0, -accelMS2) : 0
        }

        bench(motoring: motoringForce, regenerating: electricBrakeForce, speedMS: v,
              powered: regime != .off)
        torquePct = max(-100, min(100,
            (motoringForce - electricBrakeForce - frictionForce) / Self.fullEffortN * 100))

        // Low-voltage side: the static converter runs off the line behind
        // KG; the battery floats on it and slowly sags without it.
        let powered = regime != .off
        converterV = powered
            ? 112 - (Self.lineVoltage - lineVoltageV) * 0.01
            : max(0, converterV - 40 * dt)
        batteryV = powered ? 76.5 : max(72, batteryV - 0.005 * dt)
        lightingA = powered ? 15 + (headlights ? 2 : 0) : 0

        // Air: the compressor works off the converter between 7.4 and
        // 9.0 bar; friction braking draws on the reservoir.
        if !powered || converterV < 80 {
            compressorRunning = false
        } else if mainReservoirBar < 7.4 {
            compressorRunning = true
        } else if mainReservoirBar > 9.0 {
            compressorRunning = false
        }
        let frictionShare = min(1, frictionForce / (mass * 2.8))
        mainReservoirBar += ((compressorRunning ? 0.12 : 0) - 0.004 - 0.05 * frictionShare) * dt
        mainReservoirBar = max(0, min(9.5, mainReservoirBar))

        // The brake box takes the friction brakes' heat and sheds it slowly.
        brakeBoxC += (frictionForce * v / Self.brakeBoxJPerK
                      - (brakeBoxC - Self.ambientC) / Self.brakeBoxCoolingS) * dt
    }

    /// The bench picture: from the rim force, the per-car armature current,
    /// the field current of the image-série strategy, the chopper duty and
    /// the line current (il = mhi · ii per car).
    private mutating func bench(motoring: Double, regenerating regen: Double, speedMS v: Double,
                                powered: Bool) {
        let force = motoring > 0 ? motoring : regen
        guard force > 1, powered else {
            lineCurrentA = 0
            armatureCurrentA = 0
            fieldCurrentA = 0
            chopperDuty = 0
            tractionCurrentA = 0
            regenerating = false
            fieldWeakened = false
            lineVoltageV = powered ? Self.lineVoltage - 0.8 : Self.lineVoltage
            return
        }
        let omega = max(v, 0.1) / Self.wheelRadius * Self.gearRatio
        let torquePerMotor = (force / 2) * Self.wheelRadius / (2 * Self.gearRatio)
        var ratio = Self.fullField
        var ii = (torquePerMotor / (Self.torquePerAmp2 * ratio)).squareRoot()
        func loopVoltage(_ ii: Double, _ ratio: Double) -> Double {
            2 * Self.torquePerAmp2 * ratio * ii * omega + ii * Self.armatureResistance
        }
        // Regeneration never weakens the field.
        if motoring > 0, loopVoltage(ii, ratio) > Self.lineVoltage {
            ratio = Self.weakField
            ii = (torquePerMotor / (Self.torquePerAmp2 * ratio)).squareRoot()
        }
        ii = min(ii, Self.armatureCurrentMax)
        let duty = min(1, max(0, loopVoltage(ii, ratio) / Self.lineVoltage))

        armatureCurrentA = ii
        fieldCurrentA = ratio * ii
        chopperDuty = duty
        tractionCurrentA = 2 * ii
        regenerating = motoring <= 0
        fieldWeakened = ratio == Self.weakField
        lineCurrentA = 2 * duty * ii * (regenerating ? -Self.regenReceptivity : 1)
        lineVoltageV = regenerating
            ? min(825, Self.lineVoltage + abs(lineCurrentA) * 0.15)
            : Self.lineVoltage - lineCurrentA * 0.02
    }
}
