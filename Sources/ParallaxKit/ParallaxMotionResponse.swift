import Foundation
import simd

/// Converts orientation into a bounded, recentering virtual eye. It never
/// rotates the rendering camera. Feed its poses into ParallaxProjection, or a
/// ParallaxTracker with smoothingTime = 0 for missing-input fallback.
///
/// Own on one executor. The first accepted sample (at ANY holding angle) is
/// neutral. Input timestamps drive all filtering, not the display's frame rate.
public struct ParallaxMotionResponse: Sendable {
    public let configuration: ParallaxMotionConfiguration
    private var neutral: simd_quatf?
    private var lastTimestamp: TimeInterval?
    private var lastOrientation: ParallaxDisplayOrientation?
    private var offset = SIMD2<Float>.zero

    public init(configuration: ParallaxMotionConfiguration) {
        self.configuration = configuration
    }

    /// Clears the reference. The next valid sample becomes the new center.
    public mutating func reset() {
        neutral = nil
        lastTimestamp = nil
        lastOrientation = nil
        offset = .zero
    }

    /// Invalid, repeated, and out-of-order samples return nil without changing
    /// state. On a stream restart, call reset() if its clock also restarts.
    public mutating func submit(
        _ sample: ParallaxMotionSample,
        orientation: ParallaxDisplayOrientation = .portrait
    ) -> ParallaxPose? {
        let vector = sample.referenceToDevice.vector
        let length = simd_length(vector)
        guard sample.timestamp.isFinite,
              lastTimestamp.map({ sample.timestamp > $0 }) ?? true,
              vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.w.isFinite,
              length.isFinite, length > 0.00001 else { return nil }
        let current = simd_quatf(vector: vector / length)
        let dt = lastTimestamp.map { sample.timestamp - $0 } ?? 0
        defer {
            lastTimestamp = sample.timestamp
            lastOrientation = orientation
        }
        guard var reference = neutral, dt <= configuration.maximumSampleGap,
              lastOrientation == orientation else {
            neutral = current
            offset = .zero
            return .init(position: configuration.neutralPosition, timestamp: sample.timestamp)
        }

        // Integrate with bounded substeps, following the shortest quaternion
        // arc. This handles angle wrapping and arbitrary starting orientations.
        // Substeps also keep recenter + smoothing consistent at 30/60/120 Hz.
        let steps = max(1, Int(ceil(min(dt, 1) * 240)))
        let step = dt / Double(steps)
        for _ in 0..<steps {
            if let time = configuration.recenterTime {
                reference = simd_normalize(simd_slerp(reference, current, Float(1 - exp(-step / time))))
            }
            // A hypothetical viewer fixed along the neutral display normal,
            // expressed in CURRENT device axes. Screen roll alone leaves it
            // unchanged; sideways/upward tilt moves the eye, never the camera's
            // rotation. Fixed Z makes this an intentional small-motion model.
            let viewer = (current * reference.inverse).act(SIMD3<Float>(0, 0, 1))
            let angles = orientation.displayAxes(SIMD2<Float>(
                atan2(viewer.x, max(viewer.z, 0.0001)),
                atan2(viewer.y, max(viewer.z, 0.0001))
            ))
            let tilt = simd_clamp(angles * configuration.sensitivity,
                                  -configuration.maximumTilt, configuration.maximumTilt)
            let target = simd_clamp(
                SIMD2<Float>(tan(tilt.x), tan(tilt.y)) * configuration.viewerDistance,
                -configuration.maximumOffset, configuration.maximumOffset
            )
            let alpha: Float = configuration.smoothingTime == 0
                ? 1 : Float(1 - exp(-step / configuration.smoothingTime))
            offset += (target - offset) * alpha
        }
        neutral = reference
        return .init(position: [offset.x, offset.y, configuration.viewerDistance], timestamp: sample.timestamp)
    }
}
