//
//  TrackGeometry.swift
//  VALPupitreSim
//

import RealityKit
import simd

/// Where a guideway runs through a RealityKit scene. A track maps a distance
/// along the line to a frame — a point, the heading there and the right-hand
/// side — so the scenes lay out the guideway, the stations and the rame the
/// same way on the straight test track and on a PCC's loop. Up is always +Y.
protocol SceneTrack {
    /// Length of the centreline, in scene units.
    var length: Float { get }
    /// A loop: distance wraps round, and a whole lap closes on itself.
    var isClosed: Bool { get }
    /// No curves anywhere, so a swept bar needs a single facet.
    var isStraight: Bool { get }
    func frame(at s: Float) -> TrackFrame
}

/// A point on a track and the way the track runs there.
struct TrackFrame {
    var origin: SIMD3<Float>
    /// Unit vector along the track, towards increasing distance.
    var forward: SIMD3<Float>

    /// Unit vector to the right of `forward`, level.
    var right: SIMD3<Float> { simd_cross(forward, [0, 1, 0]) }

    /// The point `x` to the right of the centreline and `y` up.
    func point(x: Float = 0, y: Float = 0) -> SIMD3<Float> {
        origin + right * x + SIMD3<Float>(0, y, 0)
    }

    /// Turns a model built facing -Z (a car, a camera) to face along the track.
    var orientation: simd_quatf {
        simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0])
    }

    var transform: Transform {
        Transform(scale: .one, rotation: orientation, translation: origin)
    }
}

/// The test track: straight down -Z from the origin, one unit per metre.
struct StraightSceneTrack: SceneTrack {
    var length: Float
    var isClosed: Bool { false }
    var isStraight: Bool { true }

    func frame(at s: Float) -> TrackFrame {
        TrackFrame(origin: [0, 0, -s], forward: [0, 0, -1])
    }
}

/// A loop laid out as a circle of the line's length, one unit per metre.
/// Distance 0 sits at the origin heading -Z, as on the test track, and the
/// line curves right: seen from above the rame runs clockwise, the same way
/// round as on the overview map.
struct CircleSceneTrack: SceneTrack {
    var length: Float
    var isClosed: Bool { true }
    var isStraight: Bool { false }
    var radius: Float { length / (2 * .pi) }

    func frame(at s: Float) -> TrackFrame {
        let angle = s / radius
        return TrackFrame(origin: [radius - radius * cos(angle), 0, -radius * sin(angle)],
                          forward: [sin(angle), 0, -cos(angle)])
    }
}

/// A loop drawn as a racetrack — two straights joined by half circles — for
/// the overview strip, which is far wider than it is tall. It lies in the
/// XZ plane around the origin; distance 0 is the left end of the top straight
/// (-Z is up on the map), heading right, so the rame runs clockwise.
struct RacetrackSceneTrack: SceneTrack {
    var straight: Float
    var radius: Float
    var length: Float { 2 * straight + 2 * .pi * radius }
    var isClosed: Bool { true }
    var isStraight: Bool { false }

    func frame(at s: Float) -> TrackFrame {
        var u = s.truncatingRemainder(dividingBy: length)
        if u < 0 { u += length }
        let half = straight / 2
        let arc = Float.pi * radius
        if u < straight {
            return TrackFrame(origin: [-half + u, 0, -radius], forward: [1, 0, 0])
        }
        u -= straight
        if u < arc {
            let angle = u / radius
            return TrackFrame(origin: [half + radius * sin(angle), 0, -radius * cos(angle)],
                              forward: [cos(angle), 0, sin(angle)])
        }
        u -= arc
        if u < straight {
            return TrackFrame(origin: [half - u, 0, radius], forward: [-1, 0, 0])
        }
        u -= straight
        let angle = u / radius
        return TrackFrame(origin: [-half - radius * sin(angle), 0, radius * cos(angle)],
                          forward: [-cos(angle), 0, -sin(angle)])
    }
}

/// The four corners of a swept bar's cross-section at one point of the track.
private struct BarSection {
    var bl, br, tr, tl: SIMD3<Float>
}

extension RK {
    /// A bar of rectangular section swept along `track` from `s0` to `s1`:
    /// `width` × `height`, centred `x` right of the centreline and `y` up. On
    /// a curve it is built in facets of about `step` units so it follows the
    /// line; a whole lap of a loop joins up with itself, anything shorter is
    /// capped at both ends.
    static func sweptBar(along track: some SceneTrack, from s0: Float, to s1: Float,
                         width: Float, height: Float, x: Float = 0, y: Float = 0,
                         step: Float = 4, _ material: some RealityKit.Material) -> ModelEntity {
        let span = s1 - s0
        let facets = track.isStraight ? 1 : max(1, Int((span / step).rounded(.up)))
        let isLap = track.isClosed && span >= track.length - 0.001

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Each face gets its own vertices so its normal stays flat. The
        // corners are taken in order round the quad; the winding is checked
        // against the outward normal rather than worked out by hand.
        func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                  facing normal: SIMD3<Float>) {
            let base = UInt32(positions.count)
            positions += [a, b, c, d]
            normals += [normal, normal, normal, normal]
            if simd_dot(simd_cross(b - a, c - a), normal) >= 0 {
                indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            } else {
                indices += [base, base + 2, base + 1, base, base + 3, base + 2]
            }
        }

        func section(_ f: TrackFrame) -> BarSection {
            BarSection(bl: f.point(x: x - width / 2, y: y - height / 2),
                       br: f.point(x: x + width / 2, y: y - height / 2),
                       tr: f.point(x: x + width / 2, y: y + height / 2),
                       tl: f.point(x: x - width / 2, y: y + height / 2))
        }

        let up = SIMD3<Float>(0, 1, 0)
        var previous = section(track.frame(at: s0))
        for i in 1...facets {
            let s = s0 + span * Float(i) / Float(facets)
            let next = section(track.frame(at: s))
            let side = track.frame(at: s - span / Float(facets) / 2).right
            quad(previous.tl, previous.tr, next.tr, next.tl, facing: up)
            quad(previous.bl, previous.br, next.br, next.bl, facing: -up)
            quad(previous.br, previous.tr, next.tr, next.br, facing: side)
            quad(previous.bl, previous.tl, next.tl, next.bl, facing: -side)
            previous = next
        }
        if !isLap {
            let start = track.frame(at: s0)
            let end = track.frame(at: s1)
            let a = section(start)
            let b = section(end)
            quad(a.bl, a.br, a.tr, a.tl, facing: -start.forward)
            quad(b.bl, b.br, b.tr, b.tl, facing: end.forward)
        }

        var descriptor = MeshDescriptor(name: "sweptBar")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return ModelEntity() }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// Adds `child` to `parent` placed at `frame`'s point (`x` right, `y`
    /// up), turned to face along the track, then by `turn` in the track's
    /// frame. Returns the child so callers can keep a reference.
    @discardableResult
    static func add<E: Entity>(_ child: E, to parent: Entity, on frame: TrackFrame,
                               x: Float = 0, y: Float = 0, turn: simd_quatf? = nil) -> E {
        child.position = frame.point(x: x, y: y)
        child.orientation = turn.map { frame.orientation * $0 } ?? frame.orientation
        parent.addChild(child)
        return child
    }
}
