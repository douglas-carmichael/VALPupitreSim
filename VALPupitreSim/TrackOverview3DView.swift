//
//  TrackOverview3DView.swift
//  VALPupitreSim
//

import SwiftUI
import RealityKit

/// A bird's-eye 3D map of the complete VAL guideway. The whole 1500 m line
/// is visible at once: stations are labeled platforms, the rame appears as a
/// coloured marker that slides along the track in sync with `model.positionM`,
/// and a small direction arrow flips when the reverser changes.
struct TrackOverview3DView: View {
    let model: SimulationModel
    @State private var rig = OverviewSceneRig()

    var body: some View {
        // Read per-frame inputs in `body` so Observation re-runs `update`.
        let positionM = Float(model.positionM)
        let direction = model.direction

        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            content.add(rig.makeScene(model: model))
        } update: { _ in
            rig.apply(positionM: positionM, direction: direction)
        }
        .realityViewCameraControls(.none)
        .backgroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
        .background(Color(red: 0.04, green: 0.05, blue: 0.08))
    }
}

@MainActor
private final class OverviewSceneRig {
    private var trainMarker = Entity()
    private var directionArrow = Entity()

    // MARK: Scene construction

    func makeScene(model: SimulationModel) -> Entity {
        let root = Entity()
        let trackLen = Float(model.trackLengthM)

        root.addChild(RK.directionalLight(intensity: 2400,
                                          orientation: RK.euler(-.pi / 2.4, .pi / 6, 0)))
        // Soft fill stands in for SceneKit's ambient light.
        root.addChild(RK.directionalLight(intensity: 900, color: PColor(white: 0.9, alpha: 1),
                                          orientation: RK.euler(-.pi / 2.2, .pi + .pi / 6, 0)))

        root.addChild(makeGuideway(length: trackLen))
        root.addChild(makeStations(model: model))

        trainMarker = makeTrainMarker()
        root.addChild(trainMarker)

        // Top-down camera. The orthographic scale fits the *vertical* extent
        // of the strip (guideway depth + platforms + labels); RealityKit then
        // stretches the horizontal extent to the view's aspect ratio, which
        // naturally fits the long 1500 m track in a wide strip.
        var ortho = OrthographicCameraComponent()
        ortho.scale = 130
        ortho.scaleDirection = .vertical
        ortho.near = 1
        ortho.far = trackLen * 3
        let camera = Entity()
        camera.components.set(ortho)
        camera.position = [trackLen / 2, 600, 18]
        camera.orientation = RK.euler(-.pi / 2, 0, 0)
        root.addChild(camera)

        return root
    }

    // MARK: Guideway

    private func makeGuideway(length: Float) -> Entity {
        let group = Entity()

        RK.add(RK.box(length, 2, 70, RK.material(PColor(white: 0.28, alpha: 1))),
               to: group, at: [length / 2, -1, 0])

        RK.add(RK.box(length, 1, 4, RK.material(.systemYellow)),
               to: group, at: [length / 2, 0.4, 0])

        // Hundred-metre tick marks
        let tickMat = RK.material(.white)
        for m in stride(from: 0, through: Int(length), by: 100) {
            RK.add(RK.box(4, 0.2, 60, tickMat), to: group, at: [Float(m), 0.05, 0])
        }

        // End caps
        let capMat = RK.material(PColor(white: 0.42, alpha: 1))
        for m in [0, Int(length)] {
            RK.add(RK.box(6, 14, 90, cornerRadius: 0.5, capMat), to: group, at: [Float(m), 7, 0])
        }

        return group
    }

    private func makeStations(model: SimulationModel) -> Entity {
        let group = Entity()
        let platformMat = RK.material(PColor(white: 0.78, alpha: 1))
        let cyanMat = RK.material(.systemCyan, emissive: .systemCyan, emissiveIntensity: 0.7)

        for (i, m) in model.stationPositions.enumerated() {
            let center = Float(m)

            for side: Float in [-1, 1] {
                RK.add(RK.box(80, 8, 26, cornerRadius: 0.6, platformMat),
                       to: group, at: [center, 4, side * 38])
            }

            // Station name, lying flat and reading "up" from the camera. The
            // font size is in metres, matching the old SceneKit point size.
            let label = RK.centeredText(model.stationNames[i],
                                        font: .boldSystemFont(ofSize: 18),
                                        extrusionDepth: 1.2,
                                        RK.material(.systemCyan, emissive: .systemCyan))
            label.scale = SIMD3(repeating: 1.6)
            RK.add(label, to: group, at: [center, 9, 85],
                   orientation: RK.euler(-.pi / 2, 0, 0))

            RK.add(RK.cylinder(radius: 6, height: 20, cyanMat), to: group, at: [center, 10, 0])
        }
        return group
    }

    // MARK: Train marker

    private func makeTrainMarker() -> Entity {
        let train = Entity()

        RK.add(RK.box(70, 14, 26, cornerRadius: 2,
                      RK.material(.white, emissive: PColor(white: 0.25, alpha: 1))),
               to: train, at: [0, 9, 0])

        RK.add(RK.box(70.4, 5, 26.4,
                      RK.material(.systemGreen, emissive: .systemGreen, emissiveIntensity: 0.5)),
               to: train, at: [0, 6, 0])

        directionArrow = RK.cone(radius: 8, height: 20,
                                 RK.material(.systemOrange, emissive: .systemOrange,
                                             emissiveIntensity: 0.7))
        directionArrow.orientation = RK.euler(0, 0, -.pi / 2)
        directionArrow.position = [50, 10, 0]
        train.addChild(directionArrow)

        return train
    }

    // MARK: Per-frame update

    func apply(positionM: Float, direction: SimulationModel.Direction) {
        trainMarker.position = [positionM, 0, 0]

        switch direction {
        case .forward:
            directionArrow.isEnabled = true
            directionArrow.orientation = RK.euler(0, 0, -.pi / 2)
            directionArrow.position = [50, 10, 0]
        case .reverse:
            directionArrow.isEnabled = true
            directionArrow.orientation = RK.euler(0, 0, .pi / 2)
            directionArrow.position = [-50, 10, 0]
        case .neutral:
            directionArrow.isEnabled = false
        }
    }
}
