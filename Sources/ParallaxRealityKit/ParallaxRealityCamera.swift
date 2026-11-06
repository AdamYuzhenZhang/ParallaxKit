import ParallaxKit
import RealityKit
import simd

@MainActor
public enum ParallaxRealityCamera {
    /// The entity's parent must use the same meter-based screen coordinate
    /// system as the scene. Use a non-AR renderer; face mode can read a separate,
    /// host-owned ARSession. Still and motion modes require no ARSession.
    public static func apply(_ camera: ParallaxCamera, to entity: Entity) {
        entity.components.remove(PerspectiveCameraComponent.self)
        entity.transform = Transform(translation: camera.position)
        entity.components.set(ProjectiveTransformCameraComponent(projectionMatrix: camera.projectionMatrix))
    }
}
