//
//  TrackOverview3DView.swift
//  VALPupitreSim
//

import SwiftUI
import SceneKit

/// A bird's-eye 3D map of the complete VAL guideway. The whole 1500 m line
/// is visible at once: stations are labeled platforms, the rame appears as a
/// coloured marker that slides along the track in sync with `model.positionM`,
/// and a small direction arrow flips when the reverser changes.
struct TrackOverview3DView: View {
    let model: SimulationModel

    var body: some View {
        OverviewSceneRepresentable(model: model)
    }
}

private final class OverviewCoordinator {
    var trainNode: SCNNode?
    var directionArrow: SCNNode?
    var trackLength: Float = 1500
}

private struct OverviewSceneRepresentable {
    let model: SimulationModel

    // MARK: Scene construction

    func makeScene(coord: OverviewCoordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = PColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)

        let trackLen = Float(model.trackLengthM)
        coord.trackLength = trackLen

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        ambient.light?.color = PColor(white: 0.9, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 600
        key.eulerAngles = SCNVector3(-Float.pi / 2.4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)

        scene.rootNode.addChildNode(makeGuideway(length: trackLen))
        scene.rootNode.addChildNode(makeStations())

        let train = makeTrainMarker(coord: coord)
        coord.trainNode = train
        scene.rootNode.addChildNode(train)

        // Top-down camera. The orthographic scale fits the *vertical* extent
        // of the strip (guideway depth + platforms + labels); SceneKit then
        // stretches the horizontal extent to the view's aspect ratio, which
        // naturally fits the long 1500 m track in a wide strip.
        let camera = SCNNode()
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = 130
        cam.zNear = 1
        cam.zFar = Double(trackLen) * 3
        camera.camera = cam
        camera.position = SCNVector3(trackLen / 2, 600, 18)
        camera.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(camera)

        return scene
    }

    // MARK: Guideway

    private func makeGuideway(length: Float) -> SCNNode {
        let group = SCNNode()

        let slab = SCNBox(width: CGFloat(length), height: 2, length: 70,
                          chamferRadius: 0)
        slab.firstMaterial?.diffuse.contents = PColor(white: 0.28, alpha: 1)
        let slabNode = SCNNode(geometry: slab)
        slabNode.position = SCNVector3(length / 2, -1, 0)
        group.addChildNode(slabNode)

        let rail = SCNBox(width: CGFloat(length), height: 1, length: 4,
                          chamferRadius: 0)
        rail.firstMaterial?.diffuse.contents = PColor.systemYellow
        let railNode = SCNNode(geometry: rail)
        railNode.position = SCNVector3(length / 2, 0.4, 0)
        group.addChildNode(railNode)

        // Hundred-metre tick marks
        for m in stride(from: 0, through: Int(length), by: 100) {
            let tick = SCNBox(width: 4, height: 0.2, length: 60,
                              chamferRadius: 0)
            tick.firstMaterial?.diffuse.contents = PColor.white
            let n = SCNNode(geometry: tick)
            n.position = SCNVector3(Float(m), 0.05, 0)
            group.addChildNode(n)
        }

        // End caps
        for m in [0, Int(length)] {
            let cap = SCNBox(width: 6, height: 14, length: 90,
                             chamferRadius: 0.5)
            cap.firstMaterial?.diffuse.contents = PColor(white: 0.42, alpha: 1)
            let n = SCNNode(geometry: cap)
            n.position = SCNVector3(Float(m), 7, 0)
            group.addChildNode(n)
        }

        return group
    }

    private func makeStations() -> SCNNode {
        let group = SCNNode()
        for (i, m) in model.stationPositions.enumerated() {
            let center = Float(m)

            for side in [Float(-1), Float(1)] {
                let platform = SCNBox(width: 80, height: 8, length: 26,
                                      chamferRadius: 0.6)
                platform.firstMaterial?.diffuse.contents =
                    PColor(white: 0.78, alpha: 1)
                let n = SCNNode(geometry: platform)
                n.position = SCNVector3(center, 4, side * 38)
                group.addChildNode(n)
            }

            let label = SCNText(string: model.stationNames[i], extrusionDepth: 1.2)
            label.font = .boldSystemFont(ofSize: 18)
            label.flatness = 0.2
            label.firstMaterial?.diffuse.contents = PColor.systemCyan
            label.firstMaterial?.emission.contents = PColor.systemCyan
            let labelScale: Float = 1.6
            let labelNode = SCNNode(geometry: label)
            labelNode.scale = SCNVector3(labelScale, labelScale, labelScale)
            labelNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            let (minB, maxB) = label.boundingBox
            let w = (maxB.x - minB.x) * CGFloat(labelScale)
            labelNode.position = SCNVector3(center - Float(w) / 2, 9, 95)
            group.addChildNode(labelNode)

            let marker = SCNCylinder(radius: 6, height: 20)
            marker.firstMaterial?.diffuse.contents = PColor.systemCyan
            marker.firstMaterial?.emission.contents =
                PColor.systemCyan.withAlphaComponent(0.7)
            let markerNode = SCNNode(geometry: marker)
            markerNode.position = SCNVector3(center, 10, 0)
            group.addChildNode(markerNode)
        }
        return group
    }

    // MARK: Train marker

    private func makeTrainMarker(coord: OverviewCoordinator) -> SCNNode {
        let train = SCNNode()

        let body = SCNBox(width: 70, height: 14, length: 26, chamferRadius: 2)
        let bodyMat = SCNMaterial()
        bodyMat.diffuse.contents = PColor.white
        bodyMat.emission.contents = PColor(white: 0.25, alpha: 1)
        body.firstMaterial = bodyMat
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 9, 0)
        train.addChildNode(bodyNode)

        let stripe = SCNBox(width: 70.4, height: 5, length: 26.4,
                            chamferRadius: 0)
        let stripeMat = SCNMaterial()
        stripeMat.diffuse.contents = PColor.systemGreen
        stripeMat.emission.contents =
            PColor.systemGreen.withAlphaComponent(0.5)
        stripe.firstMaterial = stripeMat
        let stripeNode = SCNNode(geometry: stripe)
        stripeNode.position = SCNVector3(0, 6, 0)
        train.addChildNode(stripeNode)

        let arrow = SCNCone(topRadius: 0, bottomRadius: 8, height: 20)
        arrow.firstMaterial?.diffuse.contents = PColor.systemOrange
        arrow.firstMaterial?.emission.contents =
            PColor.systemOrange.withAlphaComponent(0.7)
        let arrowNode = SCNNode(geometry: arrow)
        arrowNode.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        arrowNode.position = SCNVector3(50, 10, 0)
        train.addChildNode(arrowNode)
        coord.directionArrow = arrowNode

        return train
    }

    // MARK: Per-frame update

    func updateScene(coord: OverviewCoordinator) {
        let x = Float(model.positionM)
        coord.trainNode?.simdPosition = SIMD3<Float>(x, 0, 0)

        if let arrow = coord.directionArrow {
            switch model.direction {
            case .forward:
                arrow.isHidden = false
                arrow.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
                arrow.simdPosition = SIMD3<Float>(50, 10, 0)
            case .reverse:
                arrow.isHidden = false
                arrow.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                arrow.simdPosition = SIMD3<Float>(-50, 10, 0)
            case .neutral:
                arrow.isHidden = true
            }
        }
    }
}

// MARK: - Platform bridges

#if canImport(AppKit)
extension OverviewSceneRepresentable: NSViewRepresentable {
    func makeCoordinator() -> OverviewCoordinator { OverviewCoordinator() }
    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = makeScene(coord: context.coordinator)
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        v.backgroundColor = .black
        return v
    }
    func updateNSView(_ view: SCNView, context: Context) {
        updateScene(coord: context.coordinator)
    }
}
#else
extension OverviewSceneRepresentable: UIViewRepresentable {
    func makeCoordinator() -> OverviewCoordinator { OverviewCoordinator() }
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = makeScene(coord: context.coordinator)
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ view: SCNView, context: Context) {
        updateScene(coord: context.coordinator)
    }
}
#endif
