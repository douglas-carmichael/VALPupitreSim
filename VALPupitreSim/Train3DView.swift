//
//  Train3DView.swift
//  VALPupitreSim
//

import SwiftUI
import RealityKit

/// A RealityKit visualization of the VAL 206 train moving down a concrete
/// guideway. Bi-parting passenger doors slide open in sync with
/// `model.doorsLeftOpenness` / `model.doorsRightOpenness`; the camera trails
/// the lead car; headlight emission tracks `model.kph`.
struct Train3DView: View {
    let model: SimulationModel
    @State private var rig = TrainSceneRig()

    var body: some View {
        // Read the per-frame inputs in `body` so Observation invalidates this
        // view whenever they change; RealityView then re-runs `update`.
        let frame = TrainSceneRig.Frame(
            positionM: Float(model.positionM),
            doorsLeftOpenness: Float(model.doorsLeftOpenness),
            doorsRightOpenness: Float(model.doorsRightOpenness),
            headlightsOn: model.kph
        )

        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            content.add(rig.makeScene())
        } update: { _ in
            rig.apply(frame)
        }
        .realityViewCameraControls(.none)
        .backgroundStyle(Color(red: 0.05, green: 0.06, blue: 0.09))
        .background(Color(red: 0.05, green: 0.06, blue: 0.09))
    }
}

/// Builds the scene once and keeps references to the animated entities so
/// per-frame updates don't have to walk the entity tree.
@MainActor
private final class TrainSceneRig {
    struct Frame {
        var positionM: Float
        var doorsLeftOpenness: Float
        var doorsRightOpenness: Float
        var headlightsOn: Bool
    }

    enum TrainSide { case driverLeft, driverRight }

    struct DoorHalf {
        let entity: Entity
        let baseZ: Float
        let trainSide: TrainSide
        /// Which way this half slides when opening (-Z half slides further -,
        /// +Z half slides further +).
        let slideDirection: Float
    }

    private var train = Entity()
    private var camera = Entity()
    private var headlights: [ModelEntity] = []
    private var doorHalves: [DoorHalf] = []
    private var headlightsOn: Bool?

    private let lampOff = RK.material(PColor(white: 0.95, alpha: 1))
    private let lampOn = RK.material(PColor(white: 0.95, alpha: 1),
                                     emissive: .white, emissiveIntensity: 2)

    // MARK: Scene construction

    func makeScene() -> Entity {
        let root = Entity()

        root.addChild(RK.directionalLight(intensity: 1600, castsShadow: true,
                                          orientation: RK.euler(-.pi / 3, .pi / 5, 0)))
        // Soft fill from the opposite side stands in for SceneKit's ambient light.
        root.addChild(RK.directionalLight(intensity: 500, color: PColor(white: 0.85, alpha: 1),
                                          orientation: RK.euler(-.pi / 4, .pi + .pi / 5, 0)))

        root.addChild(makeGuideway())
        root.addChild(makeStations())

        train = makeTrain()
        train.name = "train"
        root.addChild(train)

        camera = Entity()
        camera.components.set(PerspectiveCameraComponent(near: 0.1, far: 400,
                                                         fieldOfViewInDegrees: 55))
        camera.position = [3.5, 4.2, 18]
        camera.orientation = RK.euler(-0.18, 0.18, 0)
        root.addChild(camera)

        return root
    }

    // MARK: Guideway

    private func makeGuideway() -> Entity {
        let group = Entity()
        let len: Float = 2000
        let midZ = -len / 2 + 20

        RK.add(RK.box(5.2, 0.25, len, RK.material(PColor(white: 0.32, alpha: 1))),
               to: group, at: [0, -0.7, midZ])

        // Central guide rail — the VAL trademark central beam
        RK.add(RK.box(0.18, 0.22, len, RK.material(.systemYellow)),
               to: group, at: [0, -0.45, midZ])

        // Curbs the rubber tires roll on
        for x: Float in [-1.7, 1.7] {
            RK.add(RK.box(0.6, 0.08, len, RK.material(PColor(white: 0.45, alpha: 1))),
                   to: group, at: [x, -0.52, midZ])
        }

        for x: Float in [-3.2, 3.2] {
            RK.add(RK.box(0.2, 3.0, len, RK.material(PColor(white: 0.18, alpha: 1))),
                   to: group, at: [x, 0.9, midZ])
        }

        let stripeMat = RK.material(.white)
        for m in stride(from: 0, through: 1500, by: 50) {
            RK.add(RK.box(1.0, 0.01, 0.25, stripeMat), to: group, at: [0, -0.56, -Float(m)])
        }
        return group
    }

    private func makeStations() -> Entity {
        let group = Entity()
        let mat = RK.material(PColor(white: 0.55, alpha: 1))
        for m in stride(from: 250, through: 1500, by: 500) {
            for side: Float in [-1, 1] {
                RK.add(RK.box(1.5, 1.1, 40, cornerRadius: 0.05, mat),
                       to: group, at: [side * 2.6, -0.1, -Float(m)])
            }
        }
        return group
    }

    // MARK: Train

    private func makeTrain() -> Entity {
        let train = Entity()
        for i in 0..<2 {
            let car = makeCar(isLead: i == 0)
            car.position = [0, 0, Float(i) * 13.2]
            train.addChild(car)
        }
        return train
    }

    private func makeCar(isLead: Bool) -> Entity {
        let car = Entity()

        RK.add(RK.box(2.06, 2.4, 12.8, cornerRadius: 0.25, RK.material(.white)),
               to: car, at: [0, 0.7, 0])

        RK.add(RK.box(2.08, 0.35, 12.8, RK.material(.systemGreen)),
               to: car, at: [0, -0.05, 0])

        // Window band
        let glass = RK.material(PColor(white: 0.12, alpha: 1), roughness: 0.2)
        for side: Float in [-1.04, 1.04] {
            RK.add(RK.box(0.02, 0.85, 11.5, cornerRadius: 0.05, glass),
                   to: car, at: [side, 1.05, 0])
        }

        // Three bi-parting door pairs per car, on each side
        let doorMat = RK.material(PColor(white: 0.78, alpha: 1))
        for zCenter in stride(from: Float(-4.5), through: 4.5, by: 4.5) {
            for sideX: Float in [-1.045, 1.045] {
                let trainSide: TrainSide = sideX < 0 ? .driverLeft : .driverRight

                // Each pair = two halves of length 0.55, originally centered at zCenter
                let halfLen: Float = 0.55
                let inset: Float = 0.3

                for slide: Float in [-1, 1] {
                    let baseZ = zCenter + slide * inset
                    let door = RK.add(RK.box(0.018, 1.9, halfLen, doorMat),
                                      to: car, at: [sideX, 0.6, baseZ])
                    doorHalves.append(.init(entity: door, baseZ: baseZ,
                                            trainSide: trainSide, slideDirection: slide))
                }
            }
        }

        if isLead {
            RK.add(RK.box(1.7, 0.9, 0.02, cornerRadius: 0.05,
                          RK.material(PColor(white: 0.1, alpha: 1), roughness: 0.15)),
                   to: car, at: [0, 1.35, -6.41])

            for x: Float in [-0.65, 0.65] {
                let lamp = RK.add(RK.sphere(radius: 0.13, lampOff), to: car, at: [x, 0.35, -6.42])
                headlights.append(lamp)
            }
        }
        return car
    }

    // MARK: Per-frame update

    func apply(_ frame: Frame) {
        let z = -frame.positionM
        train.position = [0, 0, z]
        camera.position = [3.5, 4.2, z + 18]

        let slideDistance: Float = 0.55
        for half in doorHalves {
            let openness = half.trainSide == .driverLeft
                ? frame.doorsLeftOpenness : frame.doorsRightOpenness
            half.entity.position.z = half.baseZ + half.slideDirection * openness * slideDistance
        }

        // Swap lamp materials only on change — replacing materials every frame
        // would force needless GPU resource updates.
        if headlightsOn != frame.headlightsOn {
            headlightsOn = frame.headlightsOn
            let mat = frame.headlightsOn ? lampOn : lampOff
            for lamp in headlights { lamp.model?.materials = [mat] }
        }
    }
}
