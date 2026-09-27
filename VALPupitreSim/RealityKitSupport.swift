//
//  RealityKitSupport.swift
//  VALPupitreSim
//

import SwiftUI
import RealityKit

#if canImport(AppKit)
import AppKit
typealias PColor = NSColor
#else
import UIKit
typealias PColor = UIColor
#endif

/// Small builders shared by the three RealityKit views (`Train3DView`,
/// `TrackOverview3DView`, `Cab3DView`). They keep the scene-construction code
/// close to the primitive-box style the scenes were originally written in.
@MainActor
enum RK {

    // MARK: Materials

    /// A matte, non-metallic PBR material. `emissive` makes the surface glow
    /// independently of scene lighting (lamps, labels, markers).
    static func material(_ color: PColor,
                         emissive: PColor? = nil,
                         emissiveIntensity: Float = 1,
                         roughness: Float = 0.6,
                         opacity: Float = 1) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        if let emissive {
            m.emissiveColor = .init(color: emissive)
            m.emissiveIntensity = emissiveIntensity
        }
        if opacity < 1 {
            m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return m
    }

    // MARK: Primitives

    /// A box centred on its origin. `cornerRadius` is clamped so thin panels
    /// with a nominal chamfer still produce valid geometry.
    static func box(_ width: Float, _ height: Float, _ depth: Float,
                    cornerRadius: Float = 0,
                    _ material: some RealityKit.Material) -> ModelEntity {
        let maxRadius = min(width, height, depth) * 0.49
        let mesh = MeshResource.generateBox(width: width, height: height, depth: depth,
                                            cornerRadius: min(cornerRadius, maxRadius))
        return ModelEntity(mesh: mesh, materials: [material])
    }

    static func sphere(radius: Float, _ material: some RealityKit.Material) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
    }

    static func cylinder(radius: Float, height: Float, _ material: some RealityKit.Material) -> ModelEntity {
        ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material])
    }

    /// A cone whose apex points along +Y.
    static func cone(radius: Float, height: Float, _ material: some RealityKit.Material) -> ModelEntity {
        ModelEntity(mesh: .generateCone(height: height, radius: radius), materials: [material])
    }

    // MARK: Transforms

    /// Rotation from pitch (x) / yaw (y) / roll (z) Euler angles in radians,
    /// composed yaw · pitch · roll — the same convention the scenes used for
    /// aiming cameras and lights.
    static func euler(_ x: Float, _ y: Float, _ z: Float) -> simd_quatf {
        simd_quatf(angle: y, axis: [0, 1, 0])
            * simd_quatf(angle: x, axis: [1, 0, 0])
            * simd_quatf(angle: z, axis: [0, 0, 1])
    }

    /// Adds `child` to `parent` at `position` (and optional rotation) and
    /// returns the child so callers can keep a reference.
    @discardableResult
    static func add<E: Entity>(_ child: E, to parent: Entity,
                               at position: SIMD3<Float>,
                               orientation: simd_quatf? = nil) -> E {
        child.position = position
        if let orientation { child.orientation = orientation }
        parent.addChild(child)
        return child
    }

    // MARK: Lights

    static func directionalLight(intensity: Float,
                                 color: PColor = .white,
                                 castsShadow: Bool = false,
                                 orientation: simd_quatf) -> Entity {
        let e = Entity()
        e.components.set(DirectionalLightComponent(color: color, intensity: intensity))
        if castsShadow {
            e.components.set(DirectionalLightComponent.Shadow(maximumDistance: 80, depthBias: 1))
        }
        e.orientation = orientation
        return e
    }

    static func pointLight(intensity: Float, color: PColor = .white,
                           attenuationRadius: Float) -> Entity {
        let e = Entity()
        e.components.set(PointLightComponent(color: color, intensity: intensity,
                                             attenuationRadius: attenuationRadius))
        return e
    }

    // MARK: Text

    /// Extruded text mesh whose local origin is the geometric centre of the
    /// glyphs, so callers can place labels by their midpoint.
    static func centeredText(_ string: String, font: MeshResource.Font, extrusionDepth: Float,
                             _ material: some RealityKit.Material) -> Entity {
        let mesh = MeshResource.generateText(string, extrusionDepth: extrusionDepth, font: font)
        let text = ModelEntity(mesh: mesh, materials: [material])
        text.position = -mesh.bounds.center
        let wrapper = Entity()
        wrapper.addChild(text)
        return wrapper
    }
}
