#if os(iOS)
import CoreMotion
import Foundation
import ParallaxKit
import simd

extension ParallaxMotionSample {
    /// Use this initializer if your app already owns a CMMotionManager. No
    /// second motion service is required. Core Motion's matrix maps reference
    /// coordinates into device coordinates; explicitly form SIMD's columns.
    public init(deviceMotion: CMDeviceMotion) {
        let r = deviceMotion.attitude.rotationMatrix
        let matrix = simd_float3x3(
            SIMD3(Float(r.m11), Float(r.m21), Float(r.m31)),
            SIMD3(Float(r.m12), Float(r.m22), Float(r.m32)),
            SIMD3(Float(r.m13), Float(r.m23), Float(r.m33))
        )
        self.init(referenceToDevice: simd_quatf(matrix), timestamp: deviceMotion.timestamp)
    }
}

public enum ParallaxMotionSourceError: Error, Sendable {
    case unavailable
    case invalidUpdateInterval
}

// Confine access to the source's main actor, while allowing Swift 6.0 to tear
// down the owned service without crossing an actor boundary from deinit.
private final class MotionManagerLifetime {
    let manager = CMMotionManager()
    deinit { manager.stopDeviceMotionUpdates() }
}

/// Optional polling source. The app explicitly starts/stops it with its scene
/// lifecycle and reads latestSample on its render clock. No ARSession, camera,
/// rendering timer, callbacks, or filtering is owned by this adapter.
@MainActor
public final class CoreMotionParallaxSource {
    private let lifetime = MotionManagerLifetime()
    private var startedAt: TimeInterval?
    private var manager: CMMotionManager { lifetime.manager }

    public init() {}

    public var isAvailable: Bool {
        manager.isDeviceMotionAvailable &&
        CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical)
    }

    public var isActive: Bool { manager.isDeviceMotionActive }

    /// A sample may repeat or be stale. ParallaxController rejects duplicate
    /// timestamps and expires stale output. Samples from before start() are
    /// withheld so a restarted stream establishes a fresh neutral.
    public var latestSample: ParallaxMotionSample? {
        guard isActive, let startedAt, let motion = manager.deviceMotion,
              motion.timestamp >= startedAt else { return nil }
        return ParallaxMotionSample(deviceMotion: motion)
    }

    public func start(updateInterval: TimeInterval = 1.0 / 60) throws {
        guard updateInterval.isFinite, updateInterval > 0 else {
            throw ParallaxMotionSourceError.invalidUpdateInterval
        }
        guard isAvailable else { throw ParallaxMotionSourceError.unavailable }
        manager.deviceMotionUpdateInterval = updateInterval
        if !isActive {
            startedAt = ProcessInfo.processInfo.systemUptime
            manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
        startedAt = nil
    }
}
#endif
