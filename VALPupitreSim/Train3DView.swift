//
//  Train3DView.swift
//  VALPupitreSim
//

import SwiftUI
import RealityKit

/// A RealityKit visualization of the VAL 206 train moving down a concrete
/// guideway — the straight test track, or a PCC's loop under PCC command.
/// Bi-parting passenger doors slide open in sync with
/// `model.doorsLeftOpenness` / `model.doorsRightOpenness`; the camera trails
/// the lead car; headlight emission tracks `model.kph`. Under PCC command the
/// other rames the PCC reports run on the same guideway.
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
            headlightsOn: model.kph,
            otherRames: model.otherRames
        )
        let layout = model.layout

        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            content.add(rig.makeScene(layout: layout))
        } update: { _ in
            rig.apply(frame)
        }
        // A different line is a different scene: rebuild it.
        .id(layout.id)
        .realityViewCameraControls(.none)
        .backgroundStyle(Color(red: 0.05, green: 0.06, blue: 0.09))
        .background(Color(red: 0.05, green: 0.06, blue: 0.09))
        .overlay(alignment: .topTrailing) {
            TrafficReadout(model: model)
                .padding(10)
        }
    }
}

/// Builds the scene once per line and keeps references to the animated
/// entities so per-frame updates don't have to walk the entity tree.
@MainActor
private final class TrainSceneRig {
    struct Frame {
        var positionM: Float
        var doorsLeftOpenness: Float
        var doorsRightOpenness: Float
        var headlightsOn: Bool
        var otherRames: [OtherRame]
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

    /// Distance between the two cars' centres.
    private static let carPitch = Float(SimulationModel.carPitchM)

    private var track: any SceneTrack = StraightSceneTrack(length: 1500)
    private var cars: [Entity] = []
    private var camera = Entity()
    private var headlights: [ModelEntity] = []
    private var doorHalves: [DoorHalf] = []
    private var headlightsOn: Bool?
    private var others = OtherRamesLayer()

    private let lampOff = RK.material(PColor(white: 0.95, alpha: 1))
    private let lampOn = RK.material(PColor(white: 0.95, alpha: 1),
                                     emissive: .white, emissiveIntensity: 2)

    // MARK: Scene construction

    func makeScene(layout: TrackLayout) -> Entity {
        track = layout.isLoop
            ? CircleSceneTrack(length: Float(layout.lengthM))
            : StraightSceneTrack(length: Float(layout.lengthM))
        cars = []
        headlights = []
        doorHalves = []
        headlightsOn = nil

        let root = Entity()

        root.addChild(RK.directionalLight(intensity: 1600, castsShadow: true,
                                          orientation: RK.euler(-.pi / 3, .pi / 5, 0)))
        // Soft fill from the opposite side stands in for SceneKit's ambient light.
        root.addChild(RK.directionalLight(intensity: 500, color: PColor(white: 0.85, alpha: 1),
                                          orientation: RK.euler(-.pi / 4, .pi + .pi / 5, 0)))

        root.addChild(makeGuideway())
        root.addChild(makeStations(layout))

        // Each car rides the track on its own, so the rame bends round a loop.
        let train = Entity()
        train.name = "train"
        for i in 0..<2 {
            let car = makeCar(isLead: i == 0)
            cars.append(car)
            train.addChild(car)
        }
        root.addChild(train)

        others = OtherRamesLayer()
        root.addChild(others.root)

        camera = Entity()
        camera.components.set(PerspectiveCameraComponent(near: 0.1, far: 400,
                                                         fieldOfViewInDegrees: 55))
        root.addChild(camera)

        return root
    }

    // MARK: Guideway

    /// The stretch of guideway to build: a whole lap of a loop; the test
    /// track with a run-off past both ends.
    private var guidewaySpan: (from: Float, to: Float) {
        track.isClosed ? (0, track.length) : (-20, track.length + 480)
    }

    private func makeGuideway() -> Entity {
        let group = Entity()
        let (s0, s1) = guidewaySpan

        group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 5.2, height: 0.25,
                                   y: -0.7, RK.material(PColor(white: 0.32, alpha: 1))))

        // Central guide rail — the VAL trademark central beam
        group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 0.18, height: 0.22,
                                   y: -0.45, RK.material(.systemYellow)))

        // Curbs the rubber tires roll on
        for x: Float in [-1.7, 1.7] {
            group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 0.6, height: 0.08,
                                       x: x, y: -0.52, RK.material(PColor(white: 0.45, alpha: 1))))
        }

        for x: Float in [-3.2, 3.2] {
            group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 0.2, height: 3.0,
                                       x: x, y: 0.9, RK.material(PColor(white: 0.18, alpha: 1))))
        }

        let stripeMat = RK.material(.white)
        for m in stride(from: Float(0), to: track.length + (track.isClosed ? 0 : 1), by: 50) {
            RK.add(RK.box(1.0, 0.01, 0.25, stripeMat), to: group, on: track.frame(at: m), y: -0.56)
        }
        return group
    }

    private func makeStations(_ layout: TrackLayout) -> Entity {
        let group = Entity()
        let mat = RK.material(PColor(white: 0.55, alpha: 1))
        for station in layout.stations {
            let s = Float(station.positionM)
            for side: Float in [-1, 1] {
                group.addChild(RK.sweptBar(along: track, from: s - 20, to: s + 20,
                                           width: 1.5, height: 1.1, x: side * 2.6, y: -0.1, mat))
            }
        }
        return group
    }

    // MARK: Train

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
        for (i, car) in cars.enumerated() {
            car.transform = track.frame(at: frame.positionM - Float(i) * Self.carPitch).transform
        }

        // Trail the rame along the track, behind and to the right.
        let trail = track.frame(at: frame.positionM - 18)
        camera.position = trail.point(x: 3.5, y: 4.2)
        camera.orientation = trail.orientation * RK.euler(-0.18, 0.18, 0)

        others.apply(frame.otherRames, on: track, camera: camera.position)

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
