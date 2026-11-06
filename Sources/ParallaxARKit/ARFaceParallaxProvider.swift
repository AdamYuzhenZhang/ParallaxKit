#if os(iOS)
import ARKit
import ParallaxKit
import UIKit
import simd

public enum ParallaxEye: String, CaseIterable, Sendable {
    case left, right, midpoint
}

public enum ParallaxCameraFacing: Sendable {
    /// ARFaceTrackingConfiguration: viewer is in front of the capture camera.
    case front
    /// ARWorldTrackingConfiguration with userFaceTrackingEnabled: viewer is
    /// behind the rear capture camera. Check supportsUserFaceTracking first.
    case back
}

/// Converts one matched ARFrame into a screen-space viewer measurement.
/// The host owns configuration, authorization, the session, and its delegate.
public struct ARFaceParallaxProvider: Sendable {
    public var eye: ParallaxEye
    public var cameraFacing: ParallaxCameraFacing
    /// Capture camera origin relative to screen center, in the package's
    /// display-aligned axes and meters. Supply calibration for this device and
    /// orientation; the package does not guess physical screen dimensions.
    public var cameraOriginInScreenSpace: SIMD3<Float>

    public init(
        eye: ParallaxEye = .midpoint,
        cameraFacing: ParallaxCameraFacing,
        cameraOriginInScreenSpace: SIMD3<Float>
    ) {
        self.eye = eye
        self.cameraFacing = cameraFacing
        self.cameraOriginInScreenSpace = cameraOriginInScreenSpace
    }

    public func pose(from frame: ARFrame, orientation: UIInterfaceOrientation) -> ParallaxPose? {
        guard orientation != .unknown,
              let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first(where: \.isTracked)
        else { return nil }
        let cameraFromWorld = frame.camera.viewMatrix(for: orientation)
        let left = cameraFromWorld * face.transform * face.leftEyeTransform
        let right = cameraFromWorld * face.transform * face.rightEyeTransform
        let p: SIMD4<Float>
        switch eye {
        case .left: p = left.columns.3
        case .right: p = right.columns.3
        case .midpoint: p = (left.columns.3 + right.columns.3) / 2
        }
        var position = SIMD3<Float>(p.x, p.y, p.z)
        if cameraFacing == .front {
            // Front view-space X already follows the viewer's horizontal
            // movement. Convert depth to positive distance out of the display
            // without mirroring X. Apply the physical camera offset afterward.
            position.z = -position.z
        }
        position += cameraOriginInScreenSpace
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite, position.z > 0.01 else { return nil }
        return ParallaxPose(position: position, timestamp: frame.timestamp)
    }
}
#endif
