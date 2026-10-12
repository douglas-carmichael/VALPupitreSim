//
//  TrackOverview3DView.swift
//  VALPupitreSim
//

import SwiftUI
import RealityKit

/// A bird's-eye 3D map of the complete VAL guideway. The whole line is
/// visible at once: stations are labeled platforms, the rame appears as a
/// coloured marker that slides along the track in sync with `model.positionM`,
/// and a small direction arrow flips when the reverser changes. The straight
/// test track is drawn to scale; a PCC's loop is drawn as a racetrack that
/// fills the strip, with its cantons ticked off. The other rames a PCC reports
/// show as blue markers carrying their numbers.
struct TrackOverview3DView: View {
    let model: SimulationModel
    @State private var rig = OverviewSceneRig()

    var body: some View {
        // Read per-frame inputs in `body` so Observation re-runs `update`.
        let positionM = Float(model.positionM)
        let direction = model.direction
        let otherRames = model.otherRames
        let layout = model.layout

        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.antialiasing = .multisample4X
            content.add(rig.makeScene(layout: layout))
        } update: { content in
            // A different line is a different map: swap it inside the same
            // view. Recreating the RealityView (`.id`) gives it a new Metal
            // layer, whose drawables can fail to allocate and leave it black.
            if rig.layoutID != layout.id {
                content.entities.removeAll()
                content.add(rig.makeScene(layout: layout))
            }
            rig.apply(positionM: positionM, direction: direction, otherRames: otherRames)
        }
        .realityViewCameraControls(.none)
        .backgroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
        .background(Color(red: 0.04, green: 0.05, blue: 0.08))
    }
}

@MainActor
private final class OverviewSceneRig {
    /// Another rame's marker, and its number lying flat above it — clear of
    /// the station pins — so it reads upright whichever way the marker is
    /// turned.
    private final class OtherMarker {
        let marker: Entity
        let label = Entity()
        var rame: String?

        init(marker: Entity) { self.marker = marker }
    }

    private var root = Entity()
    private var trainMarker = Entity()
    private var directionArrow = Entity()
    private var otherMarkers: [OtherMarker] = []
    /// How a loop is drawn, and the map units one metre of line takes; nil on
    /// the test track, which is drawn one unit per metre along +X.
    private var loopMap: (track: RacetrackSceneTrack, unitsPerMetre: Float)?

    // MARK: Scene construction

    /// The line the map was last built for.
    private(set) var layoutID: String?

    func makeScene(layout: TrackLayout) -> Entity {
        layoutID = layout.id
        let root = Entity()
        self.root = root
        otherMarkers = []

        root.addChild(RK.directionalLight(intensity: 2400,
                                          orientation: RK.euler(-.pi / 2.4, .pi / 6, 0)))
        // Soft fill stands in for SceneKit's ambient light.
        root.addChild(RK.directionalLight(intensity: 900, color: PColor(white: 0.9, alpha: 1),
                                          orientation: RK.euler(-.pi / 2.2, .pi + .pi / 6, 0)))

        if layout.isLoop {
            buildLoop(layout, into: root)
        } else {
            buildStraight(layout, into: root)
        }
        return root
    }

    /// Top-down orthographic camera. The scale fits the *vertical* extent of
    /// the strip; RealityKit stretches the horizontal extent to the view's
    /// aspect ratio, which naturally fits a long line in a wide strip.
    private func makeCamera(centerX: Float, centerZ: Float, far: Float) -> Entity {
        var ortho = OrthographicCameraComponent()
        ortho.scale = 130
        ortho.scaleDirection = .vertical
        ortho.near = 1
        ortho.far = far
        let camera = Entity()
        camera.components.set(ortho)
        camera.position = [centerX, 600, centerZ]
        camera.orientation = RK.euler(-.pi / 2, 0, 0)
        return camera
    }

    private func stationLabel(_ name: String) -> Entity {
        // Lying flat and reading "up" from the camera. The font size is in
        // metres, matching the old SceneKit point size.
        let label = RK.centeredText(name, font: .boldSystemFont(ofSize: 18), extrusionDepth: 1.2,
                                    RK.material(.systemCyan, emissive: .systemCyan))
        label.scale = SIMD3(repeating: 1.6)
        label.orientation = RK.euler(-.pi / 2, 0, 0)
        return label
    }

    // MARK: Test track (straight, to scale)

    private func buildStraight(_ layout: TrackLayout, into root: Entity) {
        loopMap = nil
        let trackLen = Float(layout.lengthM)

        root.addChild(makeGuideway(length: trackLen))
        root.addChild(makeStations(layout))

        trainMarker = makeTrainMarker()
        root.addChild(trainMarker)

        root.addChild(makeCamera(centerX: trackLen / 2, centerZ: 18, far: trackLen * 3))
    }

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

    private func makeStations(_ layout: TrackLayout) -> Entity {
        let group = Entity()
        let platformMat = RK.material(PColor(white: 0.78, alpha: 1))
        let cyanMat = RK.material(.systemCyan, emissive: .systemCyan, emissiveIntensity: 0.7)

        for station in layout.stations {
            let center = Float(station.positionM)

            for side: Float in [-1, 1] {
                RK.add(RK.box(80, 8, 26, cornerRadius: 0.6, platformMat),
                       to: group, at: [center, 4, side * 38])
            }

            RK.add(stationLabel(station.name), to: group, at: [center, 9, 85])
            RK.add(RK.cylinder(radius: 6, height: 20, cyanMat), to: group, at: [center, 10, 0])
        }
        return group
    }

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

    // MARK: PCC loop (racetrack)

    private func buildLoop(_ layout: TrackLayout, into root: Entity) {
        // Sized for the strip at the window's minimum width; a wider window
        // just leaves margin either side.
        let map = RacetrackSceneTrack(straight: 2900, radius: 50)
        let unitsPerMetre = map.length / Float(layout.lengthM)
        loopMap = (map, unitsPerMetre)

        root.addChild(RK.sweptBar(along: map, from: 0, to: map.length, width: 34, height: 2,
                                  y: -1, step: 12, RK.material(PColor(white: 0.28, alpha: 1))))
        root.addChild(RK.sweptBar(along: map, from: 0, to: map.length, width: 4, height: 1,
                                  y: 0.4, step: 12, RK.material(.systemYellow)))

        // Canton boundaries, or every hundred metres if the PCC gave none.
        let tickMat = RK.material(.white)
        let ticks = layout.blocks.isEmpty
            ? Array(stride(from: 0.0, to: layout.lengthM, by: 100))
            : layout.blocks.map(\.startM)
        for m in ticks {
            RK.add(RK.box(46, 0.2, 4, tickMat), to: root,
                   on: map.frame(at: Float(m) * unitsPerMetre), y: 0.05)
        }

        let platformMat = RK.material(PColor(white: 0.78, alpha: 1))
        let cyanMat = RK.material(.systemCyan, emissive: .systemCyan, emissiveIntensity: 0.7)
        for station in layout.stations {
            let frame = map.frame(at: Float(station.positionM) * unitsPerMetre)
            for side: Float in [-1, 1] {
                RK.add(RK.box(12, 8, 80, cornerRadius: 0.6, platformMat), to: root,
                       on: frame, x: side * 24, y: 4)
            }
            RK.add(RK.cylinder(radius: 6, height: 20, cyanMat), to: root, on: frame, y: 10)
            // The map runs clockwise, so the track's right-hand side faces
            // the infield: names go on the outside.
            RK.add(stationLabel(station.name), to: root, at: frame.point(x: -62, y: 9))
        }

        let name = RK.centeredText(layout.name, font: .boldSystemFont(ofSize: 18),
                                   extrusionDepth: 1.2,
                                   RK.material(PColor(white: 0.55, alpha: 1),
                                               emissive: PColor(white: 0.35, alpha: 1)))
        name.scale = SIMD3(repeating: 1.6)
        RK.add(name, to: root, at: [0, 9, 0], orientation: RK.euler(-.pi / 2, 0, 0))

        trainMarker = makeLoopTrainMarker()
        root.addChild(trainMarker)

        root.addChild(makeCamera(centerX: 0, centerZ: 0, far: 2000))
    }

    /// The marker for the loop map, built facing -Z so a track frame turns it
    /// along the line.
    private func makeLoopTrainMarker() -> Entity {
        let train = Entity()

        RK.add(RK.box(26, 14, 70, cornerRadius: 2,
                      RK.material(.white, emissive: PColor(white: 0.25, alpha: 1))),
               to: train, at: [0, 9, 0])

        RK.add(RK.box(26.4, 5, 70.4,
                      RK.material(.systemGreen, emissive: .systemGreen, emissiveIntensity: 0.5)),
               to: train, at: [0, 6, 0])

        directionArrow = RK.cone(radius: 8, height: 20,
                                 RK.material(.systemOrange, emissive: .systemOrange,
                                             emissiveIntensity: 0.7))
        train.addChild(directionArrow)

        return train
    }

    // MARK: Other rames

    private let otherBodyMat = RK.material(PColor(red: 0.16, green: 0.3, blue: 0.62, alpha: 1),
                                           emissive: PColor(red: 0.08, green: 0.15, blue: 0.35, alpha: 1))
    private let otherLabelMat = RK.material(.white, emissive: .white, emissiveIntensity: 0.8)

    /// Lower than this rame's marker, so this rame's stays on top where they
    /// meet. Built along +X for the test track, facing -Z for the loop.
    private func makeOtherMarker() -> OtherMarker {
        let marker = Entity()
        let alongX = loopMap == nil
        RK.add(RK.box(alongX ? 70 : 26, 12, alongX ? 26 : 70, cornerRadius: 2, otherBodyMat),
               to: marker, at: [0, 7, 0])
        let other = OtherMarker(marker: marker)
        root.addChild(marker)
        root.addChild(other.label)
        return other
    }

    private func placeOthers(_ rames: [OtherRame]) {
        while otherMarkers.count < rames.count { otherMarkers.append(makeOtherMarker()) }

        for (other, rame) in zip(otherMarkers, rames) {
            other.marker.isEnabled = true
            other.label.isEnabled = true
            let s = Float(rame.positionM)
            if let loopMap {
                let frame = loopMap.track.frame(at: s * loopMap.unitsPerMetre)
                other.marker.transform = frame.transform
                other.label.position = frame.point(y: 22)
            } else {
                other.marker.position = [s, 0, 0]
                other.label.position = [s, 22, 0]
            }
            if other.rame != rame.rame {
                other.rame = rame.rame
                other.label.children.removeAll()
                let text = RK.centeredText(rame.rame, font: .boldSystemFont(ofSize: 28),
                                           extrusionDepth: 1.2, otherLabelMat)
                text.orientation = RK.euler(-.pi / 2, 0, 0)
                other.label.addChild(text)
            }
        }

        for other in otherMarkers.dropFirst(rames.count) where other.marker.isEnabled {
            other.marker.isEnabled = false
            other.label.isEnabled = false
        }
    }

    // MARK: Per-frame update

    func apply(positionM: Float, direction: SimulationModel.Direction, otherRames: [OtherRame]) {
        placeOthers(otherRames)

        if let loopMap {
            trainMarker.transform = loopMap.track.frame(at: positionM * loopMap.unitsPerMetre).transform
            switch direction {
            case .forward:
                directionArrow.isEnabled = true
                directionArrow.orientation = RK.euler(-.pi / 2, 0, 0)
                directionArrow.position = [0, 10, -50]
            case .reverse:
                directionArrow.isEnabled = true
                directionArrow.orientation = RK.euler(.pi / 2, 0, 0)
                directionArrow.position = [0, 10, 50]
            case .neutral:
                directionArrow.isEnabled = false
            }
            return
        }

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
