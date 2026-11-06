import simd

public enum ParallaxError: Error, Equatable, Sendable {
    case invalidScreen
    case invalidClipPlanes
    case invalidViewerPosition
    case invalidTrackingConfiguration
    case invalidMotionConfiguration
}

/// A rectangle on z = 0, in meters. +X is screen-right, +Y is screen-up,
/// and +Z points out of the display toward the viewer. Scene content behind
/// the display has negative Z. Bounds describe the actual rendered viewport.
public struct ParallaxScreen: Equatable, Sendable {
    public let left: Float
    public let right: Float
    public let bottom: Float
    public let top: Float

    public init(left: Float, right: Float, bottom: Float, top: Float) throws {
        guard [left, right, bottom, top].allSatisfy(\.isFinite),
              (right - left).isFinite, (top - bottom).isFinite,
              right - left > 0.0001, top - bottom > 0.0001 else {
            throw ParallaxError.invalidScreen
        }
        self.left = left
        self.right = right
        self.bottom = bottom
        self.top = top
    }

    public init(width: Float, height: Float) throws {
        try self.init(left: -width / 2, right: width / 2, bottom: -height / 2, top: height / 2)
    }

    public var center: SIMD3<Float> { [(left + right) / 2, (bottom + top) / 2, 0] }
    public var size: SIMD2<Float> { [right - left, top - bottom] }
}
