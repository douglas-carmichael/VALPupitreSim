//
//  Cab3DView.swift
//  VALPupitreSim
//

import SwiftUI
import SceneKit

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A 3D "from-the-cab" perspective of the VAL 206 looking out the front windshield.
/// Includes the cab cockpit frame, windshield wiper, guideway, tunnel lights,
/// stations with synchronized platform doors, dynamic headlights, and a HUD overlay.
struct Cab3DView: View {
    let model: SimulationModel
    @State private var showHUD: Bool = true
    @State private var cameraPreset: CameraPreset = .driver

    enum CameraPreset: String, CaseIterable, Identifiable {
        case driver = "Conducteur"
        case center = "Centre"
        case track = "Voie"

        var id: String { rawValue }

        var offset: SIMD3<Float> {
            switch self {
            case .driver:
                return SIMD3<Float>(0.35, 1.42, -5.9)
            case .center:
                return SIMD3<Float>(0.0, 1.45, -5.9)
            case .track:
                return SIMD3<Float>(0.0, 0.9, -6.5)
            }
        }
    }

    var body: some View {
        ZStack {
            CabSceneRepresentable(model: model, cameraPreset: cameraPreset)
                .ignoresSafeArea()

            if showHUD {
                cabHUD
            }

            controlsOverlay
        }
        .background(Color.black)
    }

    // MARK: - In-Cab HUD

    private var cabHUD: some View {
        VStack {
            HStack(alignment: .top, spacing: 14) {
                // Digital Speedometer
                VStack(alignment: .leading, spacing: 2) {
                    Text("VITESSE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%04.1f", model.speedKMH))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("km/h")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Mode & Direction
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.paActive ? "PILOTE AUTO" : (model.paMode ? "PA STBY" : "PILOTE MANUEL"))
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(model.paActive ? Color.mint : (model.paMode ? Color.mint.opacity(0.4) : Color.orange))
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(model.direction.rawValue)
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(model.direction == .neutral ? Color.gray : Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Text(model.positionLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                // Station indicator
                VStack(alignment: .trailing, spacing: 3) {
                    if let here = model.currentStationName {
                        Text("À QUAI")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.green)
                        Text(here)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else if let next = model.nextStation {
                        Text("PROCHAIN ARRÊT")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.cyan)
                        Text(String(format: "%@  ·  %.0f m", next.name, next.distanceM))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("LIGNE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.gray)
                        Text("FIN DE PARCOURS")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if model.deadmanWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("VIGILANCE DÉPASSÉE — APPUYEZ SUR KACOP")
                        .font(.system(size: 12, weight: .black))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(radius: 6)
                .padding(.top, 8)
            }

            Spacer()

            // Status Bar at Bottom
            HStack(spacing: 12) {
                voyantPill("TRAC", active: model.voyantTraction, color: .green)
                voyantPill("FREIN", active: model.voyantFreinage, color: .orange)
                voyantPill("URG", active: model.voyantUrgence, color: .red)
                voyantPill("PORTES", active: model.voyantPort, color: .yellow)
                voyantPill("PHARES", active: model.kph, color: .cyan)

                Spacer()

                if model.doorsAreOpen {
                    Text("PORTES OUVERTES")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.75))
        }
    }

    private func voyantPill(_ title: String, active: Bool, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(active ? color : Color.white.opacity(0.12))
            .foregroundStyle(active ? Color.black : Color.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var controlsOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Picker("Vue", selection: $cameraPreset) {
                    ForEach(CameraPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .padding(6)
                .background(.ultraThinMaterial.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    showHUD.toggle()
                } label: {
                    Image(systemName: showHUD ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial.opacity(0.7))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Afficher / Masquer l'affichage tête haute (HUD)")

                Spacer()
            }
            .padding(.leading, 16)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - SceneCoordinator

private final class CabSceneCoordinator {
    var trainRootNode: SCNNode?
    var cabFrameNode: SCNNode?
    var cameraNode: SCNNode?
    var headlightLeftSpot: SCNNode?
    var headlightRightSpot: SCNNode?
    var wiperNode: SCNNode?
    var wiperAngle: Float = 0
    var platformDoors: [SCNNode] = []
    var stationDoorHalves: [(node: SCNNode, baseZ: Float, direction: Float, isLeft: Bool)] = []
    var shakeOffset: Float = 0
}

// MARK: - CabSceneRepresentable

private struct CabSceneRepresentable {
    let model: SimulationModel
    let cameraPreset: Cab3DView.CameraPreset

    func makeScene(coord: CabSceneCoordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = PColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        scene.fogColor = PColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        scene.fogStartDistance = 35
        scene.fogEndDistance = 220

        // Ambient night/tunnel lighting
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 180
        ambient.light?.color = PColor(white: 0.7, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Directional overhead
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 250
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sun)

        // Guideway & Environment
        scene.rootNode.addChildNode(makeGuideway())
        scene.rootNode.addChildNode(makeTunnelLighting())
        scene.rootNode.addChildNode(makeStations(coord: coord))

        // Train & Cab assembly
        let trainRoot = SCNNode()
        trainRoot.name = "trainRoot"
        scene.rootNode.addChildNode(trainRoot)
        coord.trainRootNode = trainRoot

        // Cab Interior Frame (attached to train so it travels together)
        let cabFrame = makeCabInterior(coord: coord)
        trainRoot.addChildNode(cabFrame)
        coord.cabFrameNode = cabFrame

        // Dynamic Headlights (spotlights attached to train)
        let (spotL, spotR) = makeHeadlightBeams()
        trainRoot.addChildNode(spotL)
        trainRoot.addChildNode(spotR)
        coord.headlightLeftSpot = spotL
        coord.headlightRightSpot = spotR

        // Camera inside the cab
        let camera = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 68
        cam.zNear = 0.1
        cam.zFar = 350
        camera.camera = cam
        let initialOffset = cameraPreset.offset
        camera.position = SCNVector3(initialOffset.x, initialOffset.y, initialOffset.z)
        camera.eulerAngles = SCNVector3(-0.04, 0, 0)
        coord.cameraNode = camera
        trainRoot.addChildNode(camera)

        return scene
    }

    // MARK: - Guideway

    private func makeGuideway() -> SCNNode {
        let group = SCNNode()
        let len: CGFloat = 2000

        // Concrete slab
        let slab = SCNBox(width: 5.2, height: 0.25, length: len, chamferRadius: 0)
        slab.firstMaterial?.diffuse.contents = PColor(white: 0.28, alpha: 1)
        let slabNode = SCNNode(geometry: slab)
        slabNode.position = SCNVector3(0, -0.7, -Float(len / 2) + 20)
        group.addChildNode(slabNode)

        // Trademark VAL yellow central guide rail
        let rail = SCNBox(width: 0.18, height: 0.22, length: len, chamferRadius: 0)
        rail.firstMaterial?.diffuse.contents = PColor.systemYellow
        let railNode = SCNNode(geometry: rail)
        railNode.position = SCNVector3(0, -0.45, -Float(len / 2) + 20)
        group.addChildNode(railNode)

        // Rubber tire running tracks (dark concrete with tire marks)
        for x in [-1.7, 1.7] {
            let curb = SCNBox(width: 0.65, height: 0.08, length: len, chamferRadius: 0)
            curb.firstMaterial?.diffuse.contents = PColor(white: 0.38, alpha: 1)
            let n = SCNNode(geometry: curb)
            n.position = SCNVector3(Float(x), -0.52, -Float(len / 2) + 20)
            group.addChildNode(n)
        }

        // Side guide bars & parapet walls
        for x in [-3.0, 3.0] {
            let wall = SCNBox(width: 0.25, height: 2.8, length: len, chamferRadius: 0)
            wall.firstMaterial?.diffuse.contents = PColor(white: 0.22, alpha: 1)
            let n = SCNNode(geometry: wall)
            n.position = SCNVector3(Float(x), 0.7, -Float(len / 2) + 20)
            group.addChildNode(n)

            // Conductor / power rail (750V) on uprights
            let pRail = SCNBox(width: 0.1, height: 0.15, length: len, chamferRadius: 0)
            pRail.firstMaterial?.diffuse.contents = PColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1)
            let pNode = SCNNode(geometry: pRail)
            pNode.position = SCNVector3(Float(x) > 0 ? Float(x) - 0.25 : Float(x) + 0.25, 0.3, -Float(len / 2) + 20)
            group.addChildNode(pNode)
        }

        // Track markers every 50m
        for m in stride(from: 0, through: 1500, by: 50) {
            let stripe = SCNBox(width: 1.2, height: 0.015, length: 0.3, chamferRadius: 0)
            stripe.firstMaterial?.diffuse.contents = PColor.white
            let s = SCNNode(geometry: stripe)
            s.position = SCNVector3(0, -0.56, -Float(m))
            group.addChildNode(s)
        }

        return group
    }

    // MARK: - Tunnel Lighting & Arches

    private func makeTunnelLighting() -> SCNNode {
        let group = SCNNode()

        // Concrete tunnel ribs and lighting fixtures every 40m
        for m in stride(from: 10, through: 1500, by: 40) {
            let arch = SCNNode()

            // Ceiling arch
            let top = SCNBox(width: 6.2, height: 0.3, length: 0.6, chamferRadius: 0)
            top.firstMaterial?.diffuse.contents = PColor(white: 0.24, alpha: 1)
            let topNode = SCNNode(geometry: top)
            topNode.position = SCNVector3(0, 3.2, -Float(m))
            arch.addChildNode(topNode)

            // Tunnel light fixture
            let lamp = SCNBox(width: 0.8, height: 0.1, length: 0.25, chamferRadius: 0.02)
            let lMat = SCNMaterial()
            lMat.diffuse.contents = PColor(white: 0.95, alpha: 1)
            lMat.emission.contents = PColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1)
            lamp.firstMaterial = lMat
            let lampNode = SCNNode(geometry: lamp)
            lampNode.position = SCNVector3(0, 3.0, -Float(m))
            arch.addChildNode(lampNode)

            // Soft omni light along tunnel
            let lightNode = SCNNode()
            let omni = SCNLight()
            omni.type = .omni
            omni.intensity = 160
            omni.color = PColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 1)
            omni.attenuationStartDistance = 5
            omni.attenuationEndDistance = 25
            lightNode.light = omni
            lightNode.position = SCNVector3(0, 2.7, -Float(m))
            arch.addChildNode(lightNode)

            group.addChildNode(arch)
        }

        return group
    }

    // MARK: - Stations

    private func makeStations(coord: CabSceneCoordinator) -> SCNNode {
        let group = SCNNode()

        for (i, m) in model.stationPositions.enumerated() {
            let center = Float(m)
            let stationName = model.stationNames[i]

            // Station hall structure
            for side in [Float(-1), Float(1)] {
                // Platform floor
                let platform = SCNBox(width: 2.2, height: 0.9, length: 50, chamferRadius: 0.05)
                platform.firstMaterial?.diffuse.contents = PColor(white: 0.65, alpha: 1)
                let pNode = SCNNode(geometry: platform)
                pNode.position = SCNVector3(side * 3.0, -0.2, -center)
                group.addChildNode(pNode)

                // Yellow warning safety tactile line
                let safetyLine = SCNBox(width: 0.15, height: 0.01, length: 50, chamferRadius: 0)
                safetyLine.firstMaterial?.diffuse.contents = PColor.systemYellow
                let sNode = SCNNode(geometry: safetyLine)
                sNode.position = SCNVector3(side * 2.05, 0.26, -center)
                group.addChildNode(sNode)

                // Platform Screen Doors (Façades de quai VAL)
                // Glazed screen with bi-parting doors at train door positions
                for zOffset in stride(from: -12.0, through: 12.0, by: 4.5) {
                    let doorCenter = -center + Float(zOffset)

                    // Door framing
                    let doorFrame = SCNBox(width: 0.05, height: 2.4, length: 1.4, chamferRadius: 0)
                    doorFrame.firstMaterial?.diffuse.contents = PColor(white: 0.3, alpha: 1)
                    let dfNode = SCNNode(geometry: doorFrame)
                    dfNode.position = SCNVector3(side * 1.95, 1.2, doorCenter)
                    group.addChildNode(dfNode)

                    // Sliding door halves
                    for slide in [Float(-1), Float(1)] {
                        let glassDoor = SCNBox(width: 0.02, height: 2.1, length: 0.55, chamferRadius: 0)
                        let gMat = SCNMaterial()
                        gMat.diffuse.contents = PColor(white: 0.7, alpha: 0.65)
                        gMat.transparency = 0.75
                        glassDoor.firstMaterial = gMat
                        let gdNode = SCNNode(geometry: glassDoor)
                        let baseZ = doorCenter + slide * 0.28
                        gdNode.position = SCNVector3(side * 1.93, 1.1, baseZ)
                        group.addChildNode(gdNode)

                        coord.stationDoorHalves.append((
                            node: gdNode,
                            baseZ: baseZ,
                            direction: slide,
                            isLeft: side < 0
                        ))
                    }
                }
            }

            // Station Roof & Lighting
            let stationCeiling = SCNBox(width: 8.5, height: 0.4, length: 55, chamferRadius: 0)
            stationCeiling.firstMaterial?.diffuse.contents = PColor(white: 0.85, alpha: 1)
            let scNode = SCNNode(geometry: stationCeiling)
            scNode.position = SCNVector3(0, 3.8, -center)
            group.addChildNode(scNode)

            // Bright station lights
            for zOffset in stride(from: -20, through: 20, by: 10) {
                let stLight = SCNNode()
                let omni = SCNLight()
                omni.type = .omni
                omni.intensity = 550
                omni.color = PColor(white: 1.0, alpha: 1)
                omni.attenuationStartDistance = 2
                omni.attenuationEndDistance = 22
                stLight.light = omni
                stLight.position = SCNVector3(0, 3.4, -center + Float(zOffset))
                group.addChildNode(stLight)
            }

            // Illuminated Station Signage
            for side in [Float(-1), Float(1)] {
                let sign = SCNBox(width: 0.08, height: 0.5, length: 4.5, chamferRadius: 0.02)
                let signMat = SCNMaterial()
                signMat.diffuse.contents = PColor.black
                sign.firstMaterial = signMat
                let signNode = SCNNode(geometry: sign)
                signNode.position = SCNVector3(side * 2.2, 2.5, -center)
                group.addChildNode(signNode)

                let text = SCNText(string: stationName, extrusionDepth: 0.02)
                text.font = .boldSystemFont(ofSize: 0.22)
                text.flatness = 0.05
                text.firstMaterial?.diffuse.contents = PColor.white
                text.firstMaterial?.emission.contents = PColor.white
                let textNode = SCNNode(geometry: text)
                textNode.position = SCNVector3(side * 2.15, 2.38, -center + 2.0)
                textNode.eulerAngles = SCNVector3(0, side > 0 ? -Float.pi / 2 : Float.pi / 2, 0)
                group.addChildNode(textNode)
            }
        }

        return group
    }

    // MARK: - Cab Cockpit Structure

    private func makeCabInterior(coord: CabSceneCoordinator) -> SCNNode {
        let cab = SCNNode()
        let frontZ: Float = -6.41

        // 1. Dashboard / Pupitre Sill (Casquette du pupitre)
        let dash = SCNBox(width: 2.02, height: 0.35, length: 0.85, chamferRadius: 0.04)
        dash.firstMaterial?.diffuse.contents = PColor(white: 0.12, alpha: 1)
        let dashNode = SCNNode(geometry: dash)
        dashNode.position = SCNVector3(0, 0.75, frontZ + 0.45)
        cab.addChildNode(dashNode)

        // Manual Driving Console Shroud (right-hand driver pod in VAL 206)
        let console = SCNBox(width: 0.75, height: 0.16, length: 0.65, chamferRadius: 0.02)
        console.firstMaterial?.diffuse.contents = PColor(white: 0.16, alpha: 1)
        let consoleNode = SCNNode(geometry: console)
        consoleNode.position = SCNVector3(0.38, 0.94, frontZ + 0.45)
        consoleNode.eulerAngles = SCNVector3(-0.15, 0, 0)
        cab.addChildNode(consoleNode)

        // Small indicator dials / speedo plate on console
        let dialPlate = SCNBox(width: 0.68, height: 0.01, length: 0.25, chamferRadius: 0.01)
        dialPlate.firstMaterial?.diffuse.contents = PColor(white: 0.08, alpha: 1)
        let dpNode = SCNNode(geometry: dialPlate)
        dpNode.position = SCNVector3(0.38, 1.03, frontZ + 0.38)
        dpNode.eulerAngles = SCNVector3(-0.15, 0, 0)
        cab.addChildNode(dpNode)

        // 2. Windshield Frame (A-Pillars & Roof Header)
        // Left A-Pillar
        let leftPillar = SCNBox(width: 0.16, height: 1.35, length: 0.22, chamferRadius: 0.03)
        leftPillar.firstMaterial?.diffuse.contents = PColor(white: 0.10, alpha: 1)
        let lpNode = SCNNode(geometry: leftPillar)
        lpNode.position = SCNVector3(-0.96, 1.45, frontZ + 0.08)
        cab.addChildNode(lpNode)

        // Right A-Pillar
        let rightPillar = SCNBox(width: 0.16, height: 1.35, length: 0.22, chamferRadius: 0.03)
        rightPillar.firstMaterial?.diffuse.contents = PColor(white: 0.10, alpha: 1)
        let rpNode = SCNNode(geometry: rightPillar)
        rpNode.position = SCNVector3(0.96, 1.45, frontZ + 0.08)
        cab.addChildNode(rpNode)

        // Top Header / Ceiling Contour
        let ceiling = SCNBox(width: 2.06, height: 0.3, length: 1.2, chamferRadius: 0.04)
        ceiling.firstMaterial?.diffuse.contents = PColor(white: 0.11, alpha: 1)
        let cNode = SCNNode(geometry: ceiling)
        cNode.position = SCNVector3(0, 2.15, frontZ + 0.6)
        cab.addChildNode(cNode)

        // Lower windshield sill / rubber seal
        let lowerSill = SCNBox(width: 1.85, height: 0.08, length: 0.12, chamferRadius: 0.02)
        lowerSill.firstMaterial?.diffuse.contents = PColor(white: 0.06, alpha: 1)
        let lsNode = SCNNode(geometry: lowerSill)
        lsNode.position = SCNVector3(0, 0.91, frontZ)
        cab.addChildNode(lsNode)

        // 3. Windshield Glass with subtle sheen
        let glass = SCNBox(width: 1.76, height: 1.05, length: 0.015, chamferRadius: 0.02)
        let glassMat = SCNMaterial()
        glassMat.diffuse.contents = PColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 0.08)
        glassMat.specular.contents = PColor.white
        glassMat.shininess = 0.95
        glassMat.transparency = 0.15
        glass.firstMaterial = glassMat
        let glassNode = SCNNode(geometry: glass)
        glassNode.position = SCNVector3(0, 1.48, frontZ - 0.01)
        cab.addChildNode(glassNode)

        // 4. Windshield Wiper
        let wiperPivot = SCNNode()
        wiperPivot.position = SCNVector3(-0.4, 0.96, frontZ - 0.03)

        // Arm
        let arm = SCNBox(width: 0.025, height: 0.45, length: 0.015, chamferRadius: 0.005)
        arm.firstMaterial?.diffuse.contents = PColor.black
        let armNode = SCNNode(geometry: arm)
        armNode.position = SCNVector3(0, 0.22, 0)
        wiperPivot.addChildNode(armNode)

        // Blade
        let blade = SCNBox(width: 0.015, height: 0.65, length: 0.015, chamferRadius: 0.005)
        blade.firstMaterial?.diffuse.contents = PColor(white: 0.15, alpha: 1)
        let bladeNode = SCNNode(geometry: blade)
        bladeNode.position = SCNVector3(0, 0.42, 0.01)
        bladeNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.6)
        wiperPivot.addChildNode(bladeNode)

        wiperPivot.eulerAngles = SCNVector3(0, 0, -Float.pi / 2.3)
        coord.wiperNode = wiperPivot
        cab.addChildNode(wiperPivot)

        // 5. Side wall framing
        for side in [-1.03, 1.03] {
            let sidePanel = SCNBox(width: 0.04, height: 1.4, length: 1.6, chamferRadius: 0.02)
            sidePanel.firstMaterial?.diffuse.contents = PColor(white: 0.13, alpha: 1)
            let spNode = SCNNode(geometry: sidePanel)
            spNode.position = SCNVector3(Float(side), 1.45, frontZ + 0.9)
            cab.addChildNode(spNode)
        }

        return cab
    }

    // MARK: - Dynamic Headlights

    private func makeHeadlightBeams() -> (SCNNode, SCNNode) {
        let spotL = SCNNode()
        let lLight = SCNLight()
        lLight.type = .spot
        lLight.spotInnerAngle = 30
        lLight.spotOuterAngle = 65
        lLight.intensity = 1800
        lLight.color = PColor(white: 1.0, alpha: 1)
        lLight.attenuationStartDistance = 10
        lLight.attenuationEndDistance = 95
        lLight.castsShadow = false
        spotL.light = lLight
        spotL.position = SCNVector3(-0.65, 0.35, -6.45)
        spotL.eulerAngles = SCNVector3(-0.06, 0.03, 0)

        let spotR = SCNNode()
        let rLight = SCNLight()
        rLight.type = .spot
        rLight.spotInnerAngle = 30
        rLight.spotOuterAngle = 65
        rLight.intensity = 1800
        rLight.color = PColor(white: 1.0, alpha: 1)
        rLight.attenuationStartDistance = 10
        rLight.attenuationEndDistance = 95
        rLight.castsShadow = false
        spotR.light = rLight
        spotR.position = SCNVector3(0.65, 0.35, -6.45)
        spotR.eulerAngles = SCNVector3(-0.06, -0.03, 0)

        return (spotL, spotR)
    }

    // MARK: - Per-Frame Update

    func updateScene(coord: CabSceneCoordinator) {
        let z = Float(-model.positionM)
        coord.trainRootNode?.simdPosition = SIMD3<Float>(0, 0, z)

        // Subtle cab vibration proportional to speed (rubber tires on concrete joints)
        let speed = Float(model.speedMS)
        if speed > 0.1 {
            coord.shakeOffset += speed * 0.08
            let verticalBob = sin(coord.shakeOffset * 8.0) * 0.003 * min(speed / 10.0, 1.0)
            let pitchBob = cos(coord.shakeOffset * 6.0) * 0.0015 * min(speed / 10.0, 1.0)

            let baseOffset = cameraPreset.offset
            coord.cameraNode?.simdPosition = SIMD3<Float>(
                baseOffset.x,
                baseOffset.y + verticalBob,
                baseOffset.z
            )
            coord.cameraNode?.eulerAngles = SCNVector3(-0.04 + pitchBob, 0, 0)
        } else {
            let baseOffset = cameraPreset.offset
            coord.cameraNode?.simdPosition = baseOffset
            coord.cameraNode?.eulerAngles = SCNVector3(-0.04, 0, 0)
        }

        // Dynamic Headlights (KPH)
        let lightsOn = model.kph
        let targetIntensity: CGFloat = lightsOn ? 1800 : 0
        coord.headlightLeftSpot?.light?.intensity = targetIntensity
        coord.headlightRightSpot?.light?.intensity = targetIntensity

        // Platform screen doors synchronized with train doors
        let openL = Float(model.doorsLeftOpenness)
        let openR = Float(model.doorsRightOpenness)
        let slideDistance: Float = 0.55

        for half in coord.stationDoorHalves {
            let openness = half.isLeft ? openL : openR
            let newZ = half.baseZ + half.direction * openness * slideDistance
            var sp = half.node.simdPosition
            sp.z = newZ
            half.node.simdPosition = sp
        }
    }
}

// MARK: - Platform bridges

#if canImport(AppKit)
extension CabSceneRepresentable: NSViewRepresentable {
    func makeCoordinator() -> CabSceneCoordinator { CabSceneCoordinator() }
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
extension CabSceneRepresentable: UIViewRepresentable {
    func makeCoordinator() -> CabSceneCoordinator { CabSceneCoordinator() }
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
