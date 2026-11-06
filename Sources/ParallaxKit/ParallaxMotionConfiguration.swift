import Foundation
import simd

/// An orientation measurement, independent of Core Motion and any renderer.
public struct ParallaxMotionSample: Sendable {
    /// Rotation from a fixed reference frame INTO portrait device coordinates:
    /// +X right, +Y toward the top, +Z out of the display. This is the convention
    /// of Core Motion's attitude rotation matrix. Keep the reference unchanged
    /// during a stream; reset the response if the source changes its reference.
    public let referenceToDevice: simd_quatf
    public let timestamp: TimeInterval

    public init(referenceToDevice: simd_quatf, timestamp: TimeInterval) {
        self.referenceToDevice = referenceToDevice
        self.timestamp = timestamp
    }
}

/// The rendered interface orientation, not the gravity-derived device pose.
/// Names follow UIInterfaceOrientation. Changing it establishes a new neutral.
public enum ParallaxDisplayOrientation: Sendable {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight

    func displayAxes(_ portrait: SIMD2<Float>) -> SIMD2<Float> {
        switch self {
        case .portrait: portrait
        case .portraitUpsideDown: -portrait
        case .landscapeLeft: [portrait.y, -portrait.x]
        case .landscapeRight: [-portrait.y, portrait.x]
        }
    }
}

public struct ParallaxMotionConfiguration: Sendable {
    /// Fixed virtual viewing distance in meters; IMU cannot measure eye distance.
    public let viewerDistance: Float
    /// Horizontal/vertical angular gain. Negative values reverse an axis.
    public let sensitivity: SIMD2<Float>
    /// Maximum virtual eye angle in radians, after applying sensitivity.
    public let maximumTilt: SIMD2<Float>
    /// Additional horizontal/vertical translation limits in meters.
    public let maximumOffset: SIMD2<Float>
    /// Exponential neutral-adaptation time constant, in seconds. nil holds the
    /// initial reference until reset. After ~3 time constants, ~95% has returned.
    public let recenterTime: TimeInterval?
    /// Exponential output-smoothing time constant. Zero follows immediately.
    public let smoothingTime: TimeInterval
    /// A longer input gap establishes a new neutral instead of replaying motion.
    public let maximumSampleGap: TimeInterval

    public init(
        viewerDistance: Float = 0.5,
        sensitivity: SIMD2<Float> = [0.6, 0.6],
        maximumTilt: SIMD2<Float> = [0.21, 0.17],
        maximumOffset: SIMD2<Float> = [0.12, 0.10],
        recenterTime: TimeInterval? = 1.2,
        smoothingTime: TimeInterval = 0.08,
        maximumSampleGap: TimeInterval = 0.5
    ) throws {
        guard viewerDistance.isFinite, viewerDistance > 0.01, viewerDistance <= 10,
              [sensitivity.x, sensitivity.y].allSatisfy({ $0.isFinite && abs($0) <= 4 }),
              [maximumTilt.x, maximumTilt.y].allSatisfy({ $0.isFinite && $0 >= 0 && $0 < .pi / 3 }),
              [maximumOffset.x, maximumOffset.y].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              recenterTime.map({ $0.isFinite && $0 > 0 }) ?? true,
              smoothingTime.isFinite, smoothingTime >= 0,
              maximumSampleGap.isFinite, maximumSampleGap > 0 else {
            throw ParallaxError.invalidMotionConfiguration
        }
        self.viewerDistance = viewerDistance
        self.sensitivity = sensitivity
        self.maximumTilt = maximumTilt
        self.maximumOffset = maximumOffset
        self.recenterTime = recenterTime
        self.smoothingTime = smoothingTime
        self.maximumSampleGap = maximumSampleGap
    }

    public var neutralPosition: SIMD3<Float> { [0, 0, viewerDistance] }
}
