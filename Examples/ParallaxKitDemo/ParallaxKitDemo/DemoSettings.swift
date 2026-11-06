import ParallaxKit

/// The demo exposes the few controls useful while looking at the scene.
/// Per-axis gain, smoothing, travel limits, and timeouts remain package options.
struct DemoSettings: Equatable {
    var viewingDistance: Float = 0.5
    var motionStrength: Float = 0.6
    var automaticallyRecenters = true
    var recenterTime: Float = 1.2

    func makeController(mode: ParallaxMode) throws -> ParallaxController {
        let center = SIMD3<Float>(0, 0, viewingDistance)
        return try ParallaxController(
            mode: mode, fixedPosition: center,
            tracking: .init(fallbackPosition: center),
            motion: .init(
                viewerDistance: viewingDistance,
                sensitivity: .init(repeating: motionStrength),
                recenterTime: automaticallyRecenters ? Double(recenterTime) : nil
            )
        )
    }
}
