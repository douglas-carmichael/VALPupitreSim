//
//  Cab3DView.swift
//  VALPupitreSim
//

import SwiftUI
import RealityKit

/// A 3D "from-the-cab" perspective of the VAL 206 looking out the front windshield.
/// Includes the cab cockpit frame, guideway, tunnel lights,
/// stations with synchronized platform doors, dynamic headlights, and a HUD overlay.
/// The guideway is the straight test track, or a PCC's loop under PCC command,
/// where the other rames the PCC reports run ahead.
struct Cab3DView: View {
    let model: SimulationModel
    @State private var showHUD: Bool = true
    @State private var cameraPreset: CameraPreset = .driver
    @State private var rig = CabSceneRig()

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
            cabScene
                .ignoresSafeArea()

            if showHUD {
                cabHUD
            }

            controlsOverlay
        }
        .background(Color.black)
    }

    // MARK: - RealityKit scene

    private var cabScene: some View {
        // Read per-frame inputs here so Observation re-runs `update`.
        let frame = CabSceneRig.Frame(
            positionM: Float(model.positionM),
            speedMS: Float(model.speedMS),
            doorsLeftOpenness: Float(model.doorsLeftOpenness),
            doorsRightOpenness: Float(model.doorsRightOpenness),
            headlightsOn: model.kph,
            cameraOffset: cameraPreset.offset,
            otherRames: model.otherRames
        )
        let background = Color(red: 0.02, green: 0.03, blue: 0.05)
        let layout = model.layout

        return RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            content.add(rig.makeScene(layout: layout, cameraOffset: frame.cameraOffset))
        } update: { content in
            // A different line is a different scene: swap it inside the same
            // view. Recreating the RealityView (`.id`) gives it a new Metal
            // layer, whose drawables can fail to allocate and leave it black.
            if rig.layoutID != layout.id {
                content.entities.removeAll()
                content.add(rig.makeScene(layout: layout, cameraOffset: frame.cameraOffset))
            }
            rig.apply(frame)
        }
        .realityViewCameraControls(.none)
        .backgroundStyle(background)
        .background(background)
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
                    if let limit = model.stopLimitDistance {
                        Text(String(format: "POINT D'ARRÊT  ·  %.0f m", max(0, limit)))
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(limit < 30 ? Color.red : Color.orange)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // The other rames on a PCC's line, which the curves and the
            // stations mostly hide.
            HStack {
                Spacer()
                TrafficReadout(model: model)
            }
            .padding(.horizontal, 16)

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
                .labelsHidden()
                // No clipping backdrop: the system segmented control brings its
                // own glass background and draws past its layout frame, so a
                // clipShape here cuts off the outer segments.
                .fixedSize()

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

// MARK: - CabSceneRig

/// Builds the cab scene once per line and keeps references to the animated
/// entities so per-frame updates don't have to walk the entity tree.
@MainActor
private final class CabSceneRig {
    struct Frame {
        var positionM: Float
        var speedMS: Float
        var doorsLeftOpenness: Float
        var doorsRightOpenness: Float
        var headlightsOn: Bool
        var cameraOffset: SIMD3<Float>
        var otherRames: [OtherRame]
    }

    /// One half of a platform screen door. It slides along the track from
    /// `baseS` as the rame's doors on the same side open.
    struct StationDoorHalf {
        let entity: Entity
        let baseS: Float
        let x: Float
        let y: Float
        let direction: Float
        let isLeft: Bool
    }

    /// Lumens for each headlight spot when KPH is on.
    private static let headlightIntensity: Float = 36_000

    private var track: any SceneTrack = StraightSceneTrack(length: 1500)
    private var trainRoot = Entity()
    private var camera = Entity()
    private var headlightSpots: [Entity] = []
    private var stationDoorHalves: [StationDoorHalf] = []
    private var shakeOffset: Float = 0
    private var headlightsOn: Bool?
    private var doorOpenness: SIMD2<Float>?
    private var others = OtherRamesLayer()

    /// The line the scene was last built for.
    private(set) var layoutID: String?

    func makeScene(layout: TrackLayout, cameraOffset: SIMD3<Float>) -> Entity {
        layoutID = layout.id
        track = layout.isLoop
            ? CircleSceneTrack(length: Float(layout.lengthM))
            : StraightSceneTrack(length: Float(layout.lengthM))
        headlightSpots = []
        stationDoorHalves = []
        headlightsOn = nil
        doorOpenness = nil

        let root = Entity()

        // Dim overhead light for the night/tunnel feel
        root.addChild(RK.directionalLight(intensity: 450,
                                          orientation: RK.euler(-.pi / 3, .pi / 4, 0)))
        // Faint fill stands in for SceneKit's ambient light.
        root.addChild(RK.directionalLight(intensity: 200, color: PColor(white: 0.7, alpha: 1),
                                          orientation: RK.euler(-.pi / 4, .pi + .pi / 4, 0)))

        // Guideway & Environment
        root.addChild(makeGuideway())
        root.addChild(makeTunnelLighting())
        root.addChild(makeStations(layout))

        others = OtherRamesLayer()
        root.addChild(others.root)

        // Train & Cab assembly
        trainRoot = Entity()
        trainRoot.name = "trainRoot"
        root.addChild(trainRoot)

        // Cab interior frame (attached to train so it travels together)
        trainRoot.addChild(makeCabInterior())

        // Dynamic headlights (spotlights attached to train)
        for (x, yaw) in [(Float(-0.65), Float(0.03)), (Float(0.65), Float(-0.03))] {
            let spot = Entity()
            spot.components.set(SpotLightComponent(color: .white,
                                                   intensity: Self.headlightIntensity,
                                                   innerAngleInDegrees: 30,
                                                   outerAngleInDegrees: 65,
                                                   attenuationRadius: 95))
            RK.add(spot, to: trainRoot, at: [x, 0.35, -6.45],
                   orientation: RK.euler(-0.06, yaw, 0))
            headlightSpots.append(spot)
        }

        // Camera inside the cab
        camera = Entity()
        camera.components.set(PerspectiveCameraComponent(near: 0.1, far: 350,
                                                         fieldOfViewInDegrees: 68))
        RK.add(camera, to: trainRoot, at: cameraOffset, orientation: RK.euler(-0.04, 0, 0))

        return root
    }

    /// Distances along the line with something every `spacing` metres from
    /// `offset`: a whole lap of a loop, or the test track end to end.
    private func marks(every spacing: Float, from offset: Float = 0) -> StrideTo<Float> {
        stride(from: offset, to: track.length + (track.isClosed ? 0 : 1), by: spacing)
    }

    // MARK: - Guideway

    private func makeGuideway() -> Entity {
        let group = Entity()
        // A whole lap of a loop; the test track with a run-off past both ends.
        let (s0, s1): (Float, Float) = track.isClosed ? (0, track.length) : (-20, track.length + 480)

        // Concrete slab
        group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 5.2, height: 0.25,
                                   y: -0.7, RK.material(PColor(white: 0.28, alpha: 1))))

        // Trademark VAL yellow central guide rail
        group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 0.18, height: 0.22,
                                   y: -0.45, RK.material(.systemYellow)))

        // Rubber tire running tracks (dark concrete with tire marks)
        for x: Float in [-1.7, 1.7] {
            group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 0.65, height: 0.08,
                                       x: x, y: -0.52, RK.material(PColor(white: 0.38, alpha: 1))))
        }

        // Side guide bars & parapet walls
        let wallMat = RK.material(PColor(white: 0.22, alpha: 1))
        let powerRailMat = RK.material(PColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1))
        for x: Float in [-3.0, 3.0] {
            group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 0.25, height: 2.8,
                                       x: x, y: 0.7, wallMat))

            // Conductor / power rail (750V) on uprights
            group.addChild(RK.sweptBar(along: track, from: s0, to: s1, width: 0.1, height: 0.15,
                                       x: x > 0 ? x - 0.25 : x + 0.25, y: 0.3, powerRailMat))
        }

        // Track markers every 50m
        let stripeMat = RK.material(.white)
        for m in marks(every: 50) {
            RK.add(RK.box(1.2, 0.015, 0.3, stripeMat), to: group, on: track.frame(at: m), y: -0.56)
        }

        return group
    }

    // MARK: - Tunnel Lighting & Arches

    private func makeTunnelLighting() -> Entity {
        let group = Entity()
        let archMat = RK.material(PColor(white: 0.24, alpha: 1))
        let warm = PColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1)
        let lampMat = RK.material(PColor(white: 0.95, alpha: 1), emissive: warm, emissiveIntensity: 2)

        // Concrete tunnel ribs and lighting fixtures every 40m
        for m in marks(every: 40, from: 10) {
            let frame = track.frame(at: m)

            // Ceiling arch
            RK.add(RK.box(6.2, 0.3, 0.6, archMat), to: group, on: frame, y: 3.2)

            // Tunnel light fixture
            RK.add(RK.box(0.8, 0.1, 0.25, cornerRadius: 0.02, lampMat), to: group, on: frame, y: 3.0)

            // Soft point light along tunnel
            RK.add(RK.pointLight(intensity: 8_000,
                                 color: PColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 1),
                                 attenuationRadius: 25),
                   to: group, on: frame, y: 2.7)
        }

        return group
    }

    // MARK: - Stations

    private func makeStations(_ layout: TrackLayout) -> Entity {
        let group = Entity()
        let platformMat = RK.material(PColor(white: 0.65, alpha: 1))
        let safetyMat = RK.material(.systemYellow)
        let frameMat = RK.material(PColor(white: 0.3, alpha: 1))
        let glassMat = RK.material(PColor(white: 0.7, alpha: 1), roughness: 0.1, opacity: 0.5)
        let ceilingMat = RK.material(PColor(white: 0.85, alpha: 1))
        let signMat = RK.material(.black)
        let signTextMat = RK.material(.white, emissive: .white)

        for station in layout.stations {
            let center = Float(station.positionM)

            // Station hall structure
            for side: Float in [-1, 1] {
                // Platform floor
                group.addChild(RK.sweptBar(along: track, from: center - 25, to: center + 25,
                                           width: 2.2, height: 0.9, x: side * 3.0, y: -0.2,
                                           platformMat))

                // Yellow warning safety tactile line
                group.addChild(RK.sweptBar(along: track, from: center - 25, to: center + 25,
                                           width: 0.15, height: 0.01, x: side * 2.05, y: 0.26,
                                           safetyMat))

                // Platform Screen Doors (Façades de quai VAL)
                // Glazed screen with bi-parting doors at train door positions
                for offset in stride(from: Float(-12), through: 12, by: 4.5) {
                    let doorCenter = center - offset

                    // Door framing
                    RK.add(RK.box(0.05, 2.4, 1.4, frameMat), to: group,
                           on: track.frame(at: doorCenter), x: side * 1.95, y: 1.2)

                    // Sliding door halves
                    for slide: Float in [-1, 1] {
                        let baseS = doorCenter - slide * 0.28
                        let door = RK.add(RK.box(0.02, 2.1, 0.55, glassMat), to: group,
                                          on: track.frame(at: baseS), x: side * 1.93, y: 1.1)
                        stationDoorHalves.append(.init(entity: door, baseS: baseS,
                                                       x: side * 1.93, y: 1.1,
                                                       direction: slide, isLeft: side < 0))
                    }
                }
            }

            // Station Roof & Lighting
            group.addChild(RK.sweptBar(along: track, from: center - 27.5, to: center + 27.5,
                                       width: 8.5, height: 0.4, y: 3.8, ceilingMat))

            // Bright station lights
            for offset in stride(from: Float(-20), through: 20, by: 10) {
                RK.add(RK.pointLight(intensity: 27_000, attenuationRadius: 22),
                       to: group, on: track.frame(at: center + offset), y: 3.4)
            }

            // Illuminated Station Signage, facing the track
            let frame = track.frame(at: center)
            for side: Float in [-1, 1] {
                RK.add(RK.box(0.08, 0.5, 4.5, cornerRadius: 0.02, signMat),
                       to: group, on: frame, x: side * 2.2, y: 2.5)

                let text = RK.centeredText(station.name, font: .boldSystemFont(ofSize: 0.22),
                                           extrusionDepth: 0.02, signTextMat)
                RK.add(text, to: group, on: frame, x: side * 2.14, y: 2.5,
                       turn: RK.euler(0, side > 0 ? -.pi / 2 : .pi / 2, 0))
            }
        }

        return group
    }

    // MARK: - Cab Cockpit Structure

    private func makeCabInterior() -> Entity {
        let cab = Entity()
        let frontZ: Float = -6.41

        // 1. Dashboard / Pupitre Sill (Casquette du pupitre)
        RK.add(RK.box(2.02, 0.35, 0.85, cornerRadius: 0.04, RK.material(PColor(white: 0.12, alpha: 1))),
               to: cab, at: [0, 0.75, frontZ + 0.45])

        // Manual Driving Console Shroud (right-hand driver pod in VAL 206)
        RK.add(RK.box(0.75, 0.16, 0.65, cornerRadius: 0.02, RK.material(PColor(white: 0.16, alpha: 1))),
               to: cab, at: [0.38, 0.94, frontZ + 0.45], orientation: RK.euler(-0.15, 0, 0))

        // Small indicator dials / speedo plate on console
        RK.add(RK.box(0.68, 0.01, 0.25, cornerRadius: 0.01, RK.material(PColor(white: 0.08, alpha: 1))),
               to: cab, at: [0.38, 1.03, frontZ + 0.38], orientation: RK.euler(-0.15, 0, 0))

        // 2. Windshield Frame (A-Pillars & Roof Header)
        let pillarMat = RK.material(PColor(white: 0.10, alpha: 1))
        for x: Float in [-0.96, 0.96] {
            RK.add(RK.box(0.16, 1.35, 0.22, cornerRadius: 0.03, pillarMat),
                   to: cab, at: [x, 1.45, frontZ + 0.08])
        }

        // Top Header / Ceiling Contour
        RK.add(RK.box(2.06, 0.3, 1.2, cornerRadius: 0.04, RK.material(PColor(white: 0.11, alpha: 1))),
               to: cab, at: [0, 2.15, frontZ + 0.6])

        // Lower windshield sill / rubber seal
        RK.add(RK.box(1.85, 0.08, 0.12, cornerRadius: 0.02, RK.material(PColor(white: 0.06, alpha: 1))),
               to: cab, at: [0, 0.91, frontZ])

        // 3. Windshield Glass with subtle sheen
        RK.add(RK.box(1.76, 1.05, 0.015, cornerRadius: 0.02,
                      RK.material(PColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1),
                                  roughness: 0.05, opacity: 0.08)),
               to: cab, at: [0, 1.48, frontZ - 0.01])

        // 4. Side wall framing
        let sideMat = RK.material(PColor(white: 0.13, alpha: 1))
        for x: Float in [-1.03, 1.03] {
            RK.add(RK.box(0.04, 1.4, 1.6, cornerRadius: 0.02, sideMat),
                   to: cab, at: [x, 1.45, frontZ + 0.9])
        }

        return cab
    }

    // MARK: - Per-Frame Update

    func apply(_ frame: Frame) {
        trainRoot.transform = track.frame(at: frame.positionM).transform

        // Subtle cab vibration proportional to speed (rubber tires on concrete joints)
        let base = frame.cameraOffset
        if frame.speedMS > 0.1 {
            shakeOffset += frame.speedMS * 0.08
            let amount = min(frame.speedMS / 10.0, 1.0)
            let verticalBob = sin(shakeOffset * 8.0) * 0.003 * amount
            let pitchBob = cos(shakeOffset * 6.0) * 0.0015 * amount
            camera.position = [base.x, base.y + verticalBob, base.z]
            camera.orientation = RK.euler(-0.04 + pitchBob, 0, 0)
        } else {
            camera.position = base
            camera.orientation = RK.euler(-0.04, 0, 0)
        }

        others.apply(frame.otherRames, on: track, camera: camera.position(relativeTo: nil))

        // Dynamic Headlights (KPH) — only touch the components on change.
        if headlightsOn != frame.headlightsOn {
            headlightsOn = frame.headlightsOn
            for spot in headlightSpots {
                spot.components[SpotLightComponent.self]?.intensity =
                    frame.headlightsOn ? Self.headlightIntensity : 0
            }
        }

        // Platform screen doors synchronized with train doors, slid along the
        // track — only re-placed when the openness changes.
        let openness = SIMD2(frame.doorsLeftOpenness, frame.doorsRightOpenness)
        if doorOpenness != openness {
            doorOpenness = openness
            let slideDistance: Float = 0.55
            for half in stationDoorHalves {
                let open = half.isLeft ? openness.x : openness.y
                let s = half.baseS - half.direction * open * slideDistance
                half.entity.position = track.frame(at: s).point(x: half.x, y: half.y)
            }
        }
    }
}
