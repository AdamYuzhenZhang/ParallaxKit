import Foundation
import simd

/// Input selection only. The host starts/stops its camera or motion services.
public enum ParallaxMode: String, CaseIterable, Sendable {
    case still, face, motion
}

public struct ParallaxState: Equatable, Sendable {
    public enum Status: Sendable { case fixed, tracking, fallback }
    public let mode: ParallaxMode
    public let position: SIMD3<Float>
    public let status: Status
}

/// Common entry point for fixed, face-tracked, and IMU-driven viewpoints.
///
/// Own this value on one executor. Submit input from optional platform adapters,
/// sample on the render clock, and pass the resulting position to
/// `ParallaxProjection.camera(viewer:screen:near:far:)`. No UI, sensor service,
/// permission request, or renderer is owned here. Lower-level APIs remain usable
/// independently when an app needs a different input or filtering pipeline.
public struct ParallaxController: Sendable {
    public private(set) var mode: ParallaxMode
    public private(set) var fixedPosition: SIMD3<Float>
    private var faceTracker: ParallaxTracker
    private var motionResponse: ParallaxMotionResponse
    private var motionTracker: ParallaxTracker
    private var lastMotionTimestamp: TimeInterval?

    /// `tracking` controls face smoothing and both modes' timeout/return timing.
    /// Motion uses its own smoothing and returns to `motion.neutralPosition`.
    /// Omitted configurations use their documented initializer defaults.
    public init(
        mode: ParallaxMode = .still,
        fixedPosition: SIMD3<Float> = [0, 0, 0.5],
        tracking: ParallaxTrackingConfiguration? = nil,
        motion: ParallaxMotionConfiguration? = nil
    ) throws {
        guard Self.isValid(fixedPosition) else { throw ParallaxError.invalidViewerPosition }
        let tracking = try tracking ?? ParallaxTrackingConfiguration()
        let motion = try motion ?? ParallaxMotionConfiguration()
        self.mode = mode
        self.fixedPosition = fixedPosition
        faceTracker = ParallaxTracker(configuration: tracking)
        motionResponse = ParallaxMotionResponse(configuration: motion)
        motionTracker = ParallaxTracker(configuration: try .init(
            fallbackPosition: motion.neutralPosition, smoothingTime: 0,
            lossTimeout: tracking.lossTimeout, returnTime: tracking.returnTime
        ))
    }

    /// A changed mode clears old poses and references. Calling with the current
    /// mode is a no-op. This does not start/stop any platform services.
    public mutating func setMode(_ mode: ParallaxMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        reset()
    }

    public mutating func setFixedPosition(_ position: SIMD3<Float>) throws {
        guard Self.isValid(position) else { throw ParallaxError.invalidViewerPosition }
        fixedPosition = position
    }

    /// Input for an inactive mode is ignored, including delayed callbacks after
    /// a mode change. Hosts must also discard callbacks from older service runs.
    @discardableResult
    public mutating func submitFacePose(_ pose: ParallaxPose) -> Bool {
        guard mode == .face else { return false }
        return faceTracker.submit(pose)
    }

    @discardableResult
    public mutating func submitMotion(
        _ sample: ParallaxMotionSample,
        orientation: ParallaxDisplayOrientation = .portrait
    ) -> Bool {
        guard mode == .motion,
              lastMotionTimestamp.map({ sample.timestamp > $0 }) ?? true,
              let pose = motionResponse.submit(sample, orientation: orientation),
              motionTracker.submit(pose) else { return false }
        lastMotionTimestamp = sample.timestamp
        return true
    }

    public mutating func sample(at time: TimeInterval) -> ParallaxState {
        let state: ParallaxTrackingState
        switch mode {
        case .still:
            return .init(mode: mode, position: fixedPosition, status: .fixed)
        case .face:
            state = faceTracker.sample(at: time)
        case .motion:
            state = motionTracker.sample(at: time)
        }
        return .init(mode: mode, position: state.position,
                     status: state.status == .tracking ? .tracking : .fallback)
    }

    /// Clear samples after a service/clock restart. Mode and settings persist.
    public mutating func reset() {
        faceTracker.reset()
        motionResponse.reset()
        motionTracker.reset()
        lastMotionTimestamp = nil
    }

    /// Known input interruption: smoothly return to fallback. Motion establishes
    /// a new neutral on the next fresh sample, while rejecting older callbacks.
    public mutating func invalidate() {
        switch mode {
        case .still: break
        case .face: faceTracker.invalidate()
        case .motion:
            motionResponse.reset()
            motionTracker.invalidate()
        }
    }

    /// Immediately center motion output; the next fresh sample sets its neutral.
    /// Retain the timestamp boundary so polling cannot reuse a pre-reset sample.
    public mutating func recenterMotion() {
        motionResponse.reset()
        motionTracker.reset()
    }

    private static func isValid(_ position: SIMD3<Float>) -> Bool {
        position.x.isFinite && position.y.isFinite && position.z.isFinite && position.z > 0.01
    }
}
