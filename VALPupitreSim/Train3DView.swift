//
//  Train3DView.swift
//  VALPupitreSim
//

import SwiftUI
import SceneKit

#if canImport(AppKit)
import AppKit
typealias PColor = NSColor
#else
import UIKit
typealias PColor = UIColor
#endif

/// A SceneKit visualization of the VAL 206 train moving down a concrete
/// guideway. Bi-parting passenger doors slide open in sync with
/// `model.doorsLeftOpenness` / `model.doorsRightOpenness`; the camera trails
/// the lead car; headlight emission tracks `model.kph`.
struct Train3DView: View {
    let model: SimulationModel

    var body: some View {
        SceneRepresentable(model: model)
    }
}

/// Persistent references to scene nodes — held by the representable's
/// coordinator so per-frame updates don't have to walk the scene tree.
private final class SceneCoordinator {
    enum TrainSide { case driverLeft, driverRight }

    struct DoorHalf {
        let node: SCNNode
        let baseZ: Float
        let trainSide: TrainSide
        /// Which way this half slides when opening (-Z half slides further -,
        /// +Z half slides further +).
        let slideDirection: Float
    }

    var trainNode: SCNNode?
    var cameraNode: SCNNode?
    var headlightNodes: [SCNNode] = []
    var doorHalves: [DoorHalf] = []
}

private struct SceneRepresentable {
    let model: SimulationModel

    // MARK: Scene construction

    func makeScene(coord: SceneCoordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = PColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1)
        scene.fogColor = PColor.black
        scene.fogStartDistance = 40
        scene.fogEndDistance = 180

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        ambient.light?.color = PColor(white: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 750
        key.light?.castsShadow = true
        key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(key)

        scene.rootNode.addChildNode(makeGuideway())
        scene.rootNode.addChildNode(makeStations())

        let train = makeTrain(coord: coord)
        train.name = "train"
        coord.trainNode = train
        scene.rootNode.addChildNode(train)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 55
        camera.camera?.zFar = 400
        camera.position = SCNVector3(3.5, 4.2, 18)
        camera.eulerAngles = SCNVector3(-0.18, 0.18, 0)
        coord.cameraNode = camera
        scene.rootNode.addChildNode(camera)

        return scene
    }

    // MARK: Guideway

    private func makeGuideway() -> SCNNode {
        let group = SCNNode()
        let len: CGFloat = 2000

        let slab = SCNBox(width: 5.2, height: 0.25, length: len, chamferRadius: 0)
        slab.firstMaterial?.diffuse.contents = PColor(white: 0.32, alpha: 1)
        let slabNode = SCNNode(geometry: slab)
        slabNode.position = SCNVector3(0, -0.7, -Float(len / 2) + 20)
        group.addChildNode(slabNode)

        // Central guide rail — the VAL trademark central beam
        let rail = SCNBox(width: 0.18, height: 0.22, length: len, chamferRadius: 0)
        rail.firstMaterial?.diffuse.contents = PColor.systemYellow
        let railNode = SCNNode(geometry: rail)
        railNode.position = SCNVector3(0, -0.45, -Float(len / 2) + 20)
        group.addChildNode(railNode)

        // Curbs the rubber tires roll on
        for x in [-1.7, 1.7] {
            let curb = SCNBox(width: 0.6, height: 0.08, length: len, chamferRadius: 0)
            curb.firstMaterial?.diffuse.contents = PColor(white: 0.45, alpha: 1)
            let n = SCNNode(geometry: curb)
            n.position = SCNVector3(Float(x), -0.52, -Float(len / 2) + 20)
            group.addChildNode(n)
        }

        for x in [-3.2, 3.2] {
            let wall = SCNBox(width: 0.2, height: 3.0, length: len, chamferRadius: 0)
            wall.firstMaterial?.diffuse.contents = PColor(white: 0.18, alpha: 1)
            let n = SCNNode(geometry: wall)
            n.position = SCNVector3(Float(x), 0.9, -Float(len / 2) + 20)
            group.addChildNode(n)
        }

        for m in stride(from: 0, through: 1500, by: 50) {
            let stripe = SCNBox(width: 1.0, height: 0.01, length: 0.25, chamferRadius: 0)
            stripe.firstMaterial?.diffuse.contents = PColor.white
            let s = SCNNode(geometry: stripe)
            s.position = SCNVector3(0, -0.56, -Float(m))
            group.addChildNode(s)
        }
        return group
    }

    private func makeStations() -> SCNNode {
        let group = SCNNode()
        for m in stride(from: 250, through: 1500, by: 500) {
            for side in [-1, 1] {
                let platform = SCNBox(width: 1.5, height: 1.1, length: 40, chamferRadius: 0.05)
                platform.firstMaterial?.diffuse.contents = PColor(white: 0.55, alpha: 1)
                let n = SCNNode(geometry: platform)
                n.position = SCNVector3(Float(side) * 2.6, -0.1, -Float(m))
                group.addChildNode(n)
            }
        }
        return group
    }

    // MARK: Train

    private func makeTrain(coord: SceneCoordinator) -> SCNNode {
        let train = SCNNode()
        for i in 0..<2 {
            let car = makeCar(isLead: i == 0, carIndex: i, coord: coord)
            car.position = SCNVector3(0, 0, Float(i) * 13.2)
            train.addChildNode(car)
        }
        return train
    }

    private func makeCar(isLead: Bool, carIndex: Int, coord: SceneCoordinator) -> SCNNode {
        let car = SCNNode()

        let body = SCNBox(width: 2.06, height: 2.4, length: 12.8, chamferRadius: 0.25)
        body.firstMaterial?.diffuse.contents = PColor.white
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.7, 0)
        car.addChildNode(bodyNode)

        let stripe = SCNBox(width: 2.08, height: 0.35, length: 12.8, chamferRadius: 0)
        stripe.firstMaterial?.diffuse.contents = PColor.systemGreen
        let stripeNode = SCNNode(geometry: stripe)
        stripeNode.position = SCNVector3(0, -0.05, 0)
        car.addChildNode(stripeNode)

        // Window band
        for side in [-1.04, 1.04] {
            let band = SCNBox(width: 0.02, height: 0.85, length: 11.5, chamferRadius: 0.05)
            let mat = SCNMaterial()
            mat.diffuse.contents = PColor(white: 0.12, alpha: 1)
            mat.specular.contents = PColor.white
            mat.shininess = 0.6
            band.firstMaterial = mat
            let n = SCNNode(geometry: band)
            n.position = SCNVector3(Float(side), 1.05, 0)
            car.addChildNode(n)
        }

        // Three bi-parting door pairs per car, on each side
        for zCenter in stride(from: -4.5, through: 4.5, by: 4.5) {
            for sideX in [-1.045, 1.045] {
                let trainSide: SceneCoordinator.TrainSide =
                    sideX < 0 ? .driverLeft : .driverRight

                // Each pair = two halves of length 0.55, originally centered at zCenter
                let halfLen: CGFloat = 0.55
                let inset: Float = 0.3

                for slide in [Float(-1), Float(1)] {
                    let door = SCNBox(width: 0.018, height: 1.9,
                                      length: halfLen, chamferRadius: 0)
                    door.firstMaterial?.diffuse.contents = PColor(white: 0.78, alpha: 1)
                    let n = SCNNode(geometry: door)
                    let baseZ = Float(zCenter) + slide * inset
                    n.position = SCNVector3(Float(sideX), 0.6, baseZ)
                    car.addChildNode(n)
                    coord.doorHalves.append(.init(
                        node: n,
                        baseZ: baseZ,
                        trainSide: trainSide,
                        slideDirection: slide
                    ))
                }
            }
        }

        if isLead {
            let ws = SCNBox(width: 1.7, height: 0.9, length: 0.02, chamferRadius: 0.05)
            let wsMat = SCNMaterial()
            wsMat.diffuse.contents = PColor(white: 0.1, alpha: 1)
            wsMat.specular.contents = PColor.white
            wsMat.shininess = 0.8
            ws.firstMaterial = wsMat
            let wsNode = SCNNode(geometry: ws)
            wsNode.position = SCNVector3(0, 1.35, -6.41)
            car.addChildNode(wsNode)

            for x in [-0.65, 0.65] {
                let lamp = SCNSphere(radius: 0.13)
                let m = SCNMaterial()
                m.diffuse.contents = PColor(white: 0.95, alpha: 1)
                m.emission.contents = PColor.black
                lamp.firstMaterial = m
                let n = SCNNode(geometry: lamp)
                n.position = SCNVector3(Float(x), 0.35, -6.42)
                car.addChildNode(n)
                coord.headlightNodes.append(n)
            }
        }
        return car
    }

    // MARK: Per-frame update

    func updateScene(coord: SceneCoordinator) {
        let z = Float(-model.positionM)
        coord.trainNode?.simdPosition = SIMD3<Float>(0, 0, z)
        coord.cameraNode?.simdPosition = SIMD3<Float>(3.5, 4.2, z + 18)

        let openL = Float(model.doorsLeftOpenness)
        let openR = Float(model.doorsRightOpenness)
        let slideDistance: Float = 0.55

        for half in coord.doorHalves {
            let openness = (half.trainSide == .driverLeft) ? openL : openR
            let newZ = half.baseZ + half.slideDirection * openness * slideDistance
            var sp = half.node.simdPosition
            sp.z = newZ
            half.node.simdPosition = sp
        }

        let on = model.kph
        for lamp in coord.headlightNodes {
            lamp.geometry?.firstMaterial?.emission.contents =
                on ? PColor(white: 1, alpha: 1) : PColor.black
        }
    }
}

// MARK: - Platform bridges

#if canImport(AppKit)
extension SceneRepresentable: NSViewRepresentable {
    func makeCoordinator() -> SceneCoordinator { SceneCoordinator() }
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
extension SceneRepresentable: UIViewRepresentable {
    func makeCoordinator() -> SceneCoordinator { SceneCoordinator() }
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
