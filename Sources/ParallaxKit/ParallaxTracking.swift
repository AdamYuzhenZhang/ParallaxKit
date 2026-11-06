import Foundation
import simd

/// A measured eye position. Timestamps must use the same monotonic clock as
/// sample(at:), e.g. ARFrame.timestamp and CACurrentMediaTime().
public struct ParallaxPose: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let timestamp: TimeInterval

    public init(position: SIMD3<Float>, timestamp: TimeInterval) {
        self.position = position
        self.timestamp = timestamp
    }
}

public struct ParallaxTrackingConfiguration: Sendable {
    public let fallbackPosition: SIMD3<Float>
    public let smoothingTime: TimeInterval
    public let lossTimeout: TimeInterval
    public let returnTime: TimeInterval

    public init(
        fallbackPosition: SIMD3<Float> = [0, 0, 0.5],
        smoothingTime: TimeInterval = 0.07,
        lossTimeout: TimeInterval = 0.4,
        returnTime: TimeInterval = 0.25
    ) throws {
        guard fallbackPosition.x.isFinite, fallbackPosition.y.isFinite,
              fallbackPosition.z.isFinite, fallbackPosition.z > 0.01,
              [smoothingTime, lossTimeout, returnTime].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw ParallaxError.invalidTrackingConfiguration
        }
        self.fallbackPosition = fallbackPosition
        self.smoothingTime = smoothingTime
        self.lossTimeout = lossTimeout
        self.returnTime = returnTime
    }
}

public struct ParallaxTrackingState: Equatable, Sendable {
    public enum Status: Sendable { case tracking, fallback }
    public let position: SIMD3<Float>
    public let status: Status
}

/// A value-type filter. Own it on one executor; submit measurements and sample
/// it on render updates. It never owns a timer, camera, ARSession, or UI state.
public struct ParallaxTracker: Sendable {
    public let configuration: ParallaxTrackingConfiguration
    private var latestPose: ParallaxPose?
    private var lastAcceptedTimestamp: TimeInterval?
    private var lastSampleTime: TimeInterval?
    private var position: SIMD3<Float>

    public init(configuration: ParallaxTrackingConfiguration) {
        self.configuration = configuration
        position = configuration.fallbackPosition
    }

    /// Rejects invalid and out-of-order measurements without corrupting state.
    @discardableResult
    public mutating func submit(_ pose: ParallaxPose) -> Bool {
        guard pose.timestamp.isFinite, pose.position.x.isFinite,
              pose.position.y.isFinite, pose.position.z.isFinite, pose.position.z > 0.01,
              lastAcceptedTimestamp.map({ pose.timestamp > $0 }) ?? true else { return false }
        latestPose = pose
        lastAcceptedTimestamp = pose.timestamp
        return true
    }

    public mutating func reset() {
        latestPose = nil
        lastAcceptedTimestamp = nil
        lastSampleTime = nil
        position = configuration.fallbackPosition
    }

    /// Marks a known interruption immediately; missing measurements otherwise
    /// expire automatically after lossTimeout.
    public mutating func invalidate() { latestPose = nil }

    public mutating func sample(at time: TimeInterval) -> ParallaxTrackingState {
        guard time.isFinite else { return .init(position: position, status: .fallback) }
        let now = max(time, lastSampleTime ?? time)
        let start = lastSampleTime ?? now
        let pose = latestPose
        let expiry = pose.map { $0.timestamp + configuration.lossTimeout } ?? -.infinity
        // Split an interval crossing the timeout so decay is independent of
        // render cadence, including after a dropped or delayed render frame.
        if let pose, now >= pose.timestamp, expiry >= start {
            advance(toward: pose.position, duration: max(0, min(now, expiry) - start), timeConstant: configuration.smoothingTime)
            // With smoothing disabled, even the first render must use the
            // current measurement rather than waiting for a second frame.
            if configuration.smoothingTime == 0, now <= expiry { position = pose.position }
        }
        if now > expiry {
            advance(toward: configuration.fallbackPosition, duration: now - max(start, expiry), timeConstant: configuration.returnTime)
        }
        lastSampleTime = now
        let tracking = pose.map { now >= $0.timestamp && now <= expiry } ?? false
        return .init(position: position, status: tracking ? .tracking : .fallback)
    }

    private mutating func advance(toward target: SIMD3<Float>, duration: TimeInterval, timeConstant: TimeInterval) {
        guard duration > 0 else { return }
        let alpha = timeConstant == 0 ? Float(1) : Float(1 - exp(-duration / timeConstant))
        position += (target - position) * alpha
    }
}
