import simd

/// Renderer-independent camera output. The camera stays perpendicular to the
/// display; do not additionally aim it at the scene center with a look-at call.
public struct ParallaxCamera: Sendable {
    public let position: SIMD3<Float>
    public let viewMatrix: simd_float4x4
    /// Right-handed, Metal depth [0, 1], reverse Z: near = 1, far = 0.
    public let projectionMatrix: simd_float4x4
}

public enum ParallaxProjection {
    /// Derives an off-axis frustum through the physical screen rectangle.
    /// Inspired by Peder Norrby's TheParallaxView; see THIRD_PARTY_NOTICES.md.
    public static func camera(
        viewer: SIMD3<Float>,
        screen: ParallaxScreen,
        near: Float = 0.01,
        far: Float = 10
    ) throws -> ParallaxCamera {
        guard near.isFinite, far.isFinite, near > 0, far > near else {
            throw ParallaxError.invalidClipPlanes
        }
        guard viewer.x.isFinite, viewer.y.isFinite, viewer.z.isFinite,
              viewer.z > near else { throw ParallaxError.invalidViewerPosition }

        let scale = near / viewer.z
        let left = (screen.left - viewer.x) * scale
        let right = (screen.right - viewer.x) * scale
        let bottom = (screen.bottom - viewer.y) * scale
        let top = (screen.top - viewer.y) * scale
        let projection = simd_float4x4(
            SIMD4(2 * near / (right - left), 0, 0, 0),
            SIMD4(0, 2 * near / (top - bottom), 0, 0),
            SIMD4((right + left) / (right - left), (top + bottom) / (top - bottom), near / (far - near), -1),
            SIMD4(0, 0, far * near / (far - near), 0)
        )
        var view = matrix_identity_float4x4
        view.columns.3 = SIMD4(-viewer.x, -viewer.y, -viewer.z, 1)
        return ParallaxCamera(position: viewer, viewMatrix: view, projectionMatrix: projection)
    }
}
