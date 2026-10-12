//
//  OtherRamesLayer.swift
//  VALPupitreSim
//

import SwiftUI
import RealityKit

/// The other rames on a PCC's line — `SimulationModel.otherRames` — in the
/// chase and cab scenes. Each is drawn as the cab draws its own rame: two
/// cars riding the track, car 1 centred on the reported position. Its lamps
/// show which way it runs, white at the leading end and red at the trailing
/// end, and its number floats above it, turned towards the camera.
///
/// Rames are kept in slots, built the first time they are needed and only
/// moved after that; slots beyond the current count are hidden.
@MainActor
final class OtherRamesLayer {
    /// Add this to the scene once; the rames live under it.
    let root = Entity()

    private final class Slot {
        let root = Entity()
        var cars: [Entity] = []
        /// Lamps at the AV end (car 1's nose) and at the AR end (car 2's tail).
        var avLamps: [ModelEntity] = []
        var arLamps: [ModelEntity] = []
        let label = Entity()
        var rame: String?
        var sense: SimulationModel.Direction?
    }

    private var slots: [Slot] = []

    private static let carLength = Float(SimulationModel.carLengthM)
    private static let carPitch = Float(SimulationModel.carPitchM)

    private let bodyMat = RK.material(.white)
    private let bandMat = RK.material(.systemGreen)
    private let glassMat = RK.material(PColor(white: 0.12, alpha: 1), roughness: 0.2)
    private let screenMat = RK.material(PColor(white: 0.1, alpha: 1), roughness: 0.15)
    private let doorMat = RK.material(PColor(white: 0.78, alpha: 1))
    private let headLamp = RK.material(PColor(white: 0.95, alpha: 1),
                                       emissive: .white, emissiveIntensity: 2)
    private let tailLamp = RK.material(PColor(red: 0.8, green: 0.05, blue: 0.05, alpha: 1),
                                       emissive: .systemRed, emissiveIntensity: 2)
    private let labelMat = RK.material(.white, emissive: .systemYellow, emissiveIntensity: 1)

    /// Place the rames for this frame. `camera` is the camera's position in
    /// the scene; the numbers turn to face it.
    func apply(_ rames: [OtherRame], on track: some SceneTrack, camera: SIMD3<Float>) {
        while slots.count < rames.count { slots.append(makeSlot()) }

        for (slot, rame) in zip(slots, rames) {
            slot.root.isEnabled = true
            let s = Float(rame.positionM)
            slot.cars[0].transform = track.frame(at: s).transform
            slot.cars[1].transform = track.frame(at: s - Self.carPitch).transform

            let label = track.frame(at: s - Self.carPitch / 2).point(y: 2.6)
            let toCamera = camera - label
            slot.label.position = label
            slot.label.orientation = simd_quatf(angle: atan2(toCamera.x, toCamera.z), axis: [0, 1, 0])

            // Rebuild the number and swap lamp materials only on change.
            if slot.rame != rame.rame {
                slot.rame = rame.rame
                slot.label.children.removeAll()
                slot.label.addChild(RK.centeredText(rame.rame, font: .boldSystemFont(ofSize: 0.6),
                                                    extrusionDepth: 0.03, labelMat))
            }
            if slot.sense != rame.sense {
                slot.sense = rame.sense
                let runsAV = rame.sense != .reverse
                for lamp in slot.avLamps { lamp.model?.materials = [runsAV ? headLamp : tailLamp] }
                for lamp in slot.arLamps { lamp.model?.materials = [runsAV ? tailLamp : headLamp] }
            }
        }

        for slot in slots.dropFirst(rames.count) where slot.root.isEnabled {
            slot.root.isEnabled = false
        }
    }

    private func makeSlot() -> Slot {
        let slot = Slot()
        let car1 = makeCar(outerEnd: -1, lamps: &slot.avLamps)
        let car2 = makeCar(outerEnd: 1, lamps: &slot.arLamps)
        slot.cars = [car1, car2]
        slot.root.addChild(car1)
        slot.root.addChild(car2)
        slot.root.addChild(slot.label)
        root.addChild(slot.root)
        return slot
    }

    /// One car, built facing -Z like the cab's own. `outerEnd` is -1 for car
    /// 1, whose nose is the rame's AV end, and +1 for car 2, whose tail is
    /// the AR end; each outer end has a windscreen and a pair of lamps.
    private func makeCar(outerEnd: Float, lamps: inout [ModelEntity]) -> Entity {
        let car = Entity()
        let length = Self.carLength

        RK.add(RK.box(2.06, 2.4, length, cornerRadius: 0.25, bodyMat), to: car, at: [0, 0.7, 0])
        RK.add(RK.box(2.08, 0.35, length, bandMat), to: car, at: [0, -0.05, 0])
        for side: Float in [-1.04, 1.04] {
            RK.add(RK.box(0.02, 0.85, length - 1.3, cornerRadius: 0.05, glassMat),
                   to: car, at: [side, 1.05, 0])
        }

        // Three door pairs a side, closed.
        for z in stride(from: Float(-4.5), through: 4.5, by: 4.5) {
            for side: Float in [-1.045, 1.045] {
                RK.add(RK.box(0.018, 1.9, 1.1, doorMat), to: car, at: [side, 0.6, z])
            }
        }

        let end = outerEnd * (length / 2 + 0.01)
        RK.add(RK.box(1.7, 0.9, 0.02, cornerRadius: 0.05, screenMat), to: car, at: [0, 1.35, end])
        for x: Float in [-0.65, 0.65] {
            lamps.append(RK.add(RK.sphere(radius: 0.13, headLamp), to: car,
                                at: [x, 0.35, end + outerEnd * 0.01]))
        }
        return car
    }
}
