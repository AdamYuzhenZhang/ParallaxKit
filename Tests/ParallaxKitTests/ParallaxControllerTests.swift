import XCTest
import simd
import ParallaxKit

/// Exercises only the public API, as an app importing the package would.
final class ParallaxControllerTests: XCTestCase {
    func testStillIgnoresSensorsAndValidatesItsViewpoint() throws {
        var controller = try ParallaxController(fixedPosition: [0.02, 0, 0.4])
        XCTAssertFalse(controller.submitFacePose(.init(position: [0.1, 0, 0.5], timestamp: 0)))
        XCTAssertFalse(controller.submitMotion(motion(angle: 0.2, at: 0)))
        XCTAssertEqual(controller.sample(at: 1).status, .fixed)
        XCTAssertEqual(controller.sample(at: 1).position, [0.02, 0, 0.4])
        try controller.setFixedPosition([0, 0.01, 0.6])
        XCTAssertEqual(controller.sample(at: 2).position, [0, 0.01, 0.6])
        XCTAssertThrowsError(try controller.setFixedPosition([0, 0, 0]))
        XCTAssertThrowsError(try ParallaxController(fixedPosition: [.nan, 0, 0.5]))
        XCTAssertEqual(controller.sample(at: 3).position, [0, 0.01, 0.6])
    }

    func testSwitchingModesClearsHistoryAndRejectsInactiveInput() throws {
        var controller = try ParallaxController(mode: .face, tracking: .init(smoothingTime: 0))
        let face = ParallaxPose(position: [0.1, 0, 0.4], timestamp: 1)
        XCTAssertTrue(controller.submitFacePose(face))
        XCTAssertEqual(controller.sample(at: 1).position, face.position)
        controller.setMode(.face) // Selecting the active mode preserves its state.
        XCTAssertEqual(controller.sample(at: 1.1).status, .tracking)
        controller.setMode(.motion)
        XCTAssertFalse(controller.submitFacePose(.init(position: [0.2, 0, 0.4], timestamp: 1.2)))
        XCTAssertEqual(controller.sample(at: 1.2).status, .fallback)
        XCTAssertTrue(controller.submitMotion(motion(angle: 1.4, at: 1.3)))
        XCTAssertEqual(controller.sample(at: 1.3).position, [0, 0, 0.5])
        controller.setMode(.face)
        XCTAssertEqual(controller.sample(at: 1.4).status, .fallback)
        XCTAssertEqual(controller.sample(at: 1.4).position, [0, 0, 0.5])
        XCTAssertFalse(controller.submitMotion(motion(angle: 0, at: 1.5)))
    }

    func testEachModeUsesItsConfiguredFallbackAndTimeout() throws {
        var controller = try ParallaxController(
            mode: .face,
            tracking: .init(fallbackPosition: [0, 0, 0.7], smoothingTime: 0, lossTimeout: 0.2, returnTime: 0),
            motion: .init(viewerDistance: 0.4, recenterTime: nil, smoothingTime: 0)
        )
        controller.submitFacePose(.init(position: [0.1, 0, 0.5], timestamp: 0))
        XCTAssertEqual(controller.sample(at: 0).status, .tracking)
        XCTAssertEqual(controller.sample(at: 0.3).position, [0, 0, 0.7])
        controller.setMode(.motion)
        controller.submitMotion(motion(angle: 0, at: 1))
        controller.submitMotion(motion(angle: 0.2, at: 1.1))
        XCTAssertGreaterThan(controller.sample(at: 1.1).position.x, 0.01)
        let expired = controller.sample(at: 1.4)
        XCTAssertEqual(expired.status, .fallback)
        XCTAssertEqual(expired.position, [0, 0, 0.4])
    }

    func testMotionRecenterRejectsCachedSampleAndSeedsFromNextFreshPose() throws {
        var controller = try ParallaxController(mode: .motion, motion: .init(recenterTime: nil, smoothingTime: 0))
        controller.submitMotion(motion(angle: 0, at: 0))
        controller.submitMotion(motion(angle: 0.2, at: 0.1))
        XCTAssertGreaterThan(controller.sample(at: 0.1).position.x, 0.01)
        controller.recenterMotion()
        XCTAssertFalse(controller.submitMotion(motion(angle: 0.2, at: 0.1)))
        XCTAssertEqual(controller.sample(at: 0.11).position, [0, 0, 0.5])
        XCTAssertTrue(controller.submitMotion(motion(angle: 0.8, at: 0.2)))
        XCTAssertEqual(controller.sample(at: 0.2).position, [0, 0, 0.5])
    }

    func testInterruptionsRejectOldInputAndResetAllowsNewClock() throws {
        var controller = try ParallaxController(mode: .face, tracking: .init(smoothingTime: 0, returnTime: 0))
        controller.submitFacePose(.init(position: [0.1, 0, 0.4], timestamp: 10))
        _ = controller.sample(at: 10)
        controller.invalidate()
        XCTAssertFalse(controller.submitFacePose(.init(position: [0.2, 0, 0.4], timestamp: 9)))
        XCTAssertEqual(controller.sample(at: 10.1).status, .fallback)
        controller.setMode(.motion)
        controller.submitMotion(motion(angle: 0, at: 11))
        controller.invalidate()
        XCTAssertFalse(controller.submitMotion(motion(angle: 0.2, at: 10.9)))
        XCTAssertTrue(controller.submitMotion(motion(angle: 0.7, at: 11.1)))
        XCTAssertEqual(controller.sample(at: 11.1).position, [0, 0, 0.5])
        controller.reset()
        XCTAssertTrue(controller.submitMotion(motion(angle: 0.3, at: 0)))
        XCTAssertEqual(controller.sample(at: 0).status, .tracking)
    }

    func testAllModesUseTheSameScreenRegisteredProjection() throws {
        var controller = try ParallaxController(fixedPosition: [0.04, 0.02, 0.5], tracking: .init(smoothingTime: 0))
        let screen = try ParallaxScreen(width: 0.07, height: 0.15)
        for mode in ParallaxMode.allCases {
            controller.setMode(mode)
            if mode == .face { controller.submitFacePose(.init(position: [-0.08, 0.02, 0.3], timestamp: 1)) }
            if mode == .motion {
                controller.submitMotion(motion(angle: 0, at: 0.9))
                controller.submitMotion(motion(angle: 0.2, at: 1))
            }
            let state = controller.sample(at: 1)
            XCTAssertEqual(state.mode, mode)
            let camera = try ParallaxProjection.camera(viewer: state.position, screen: screen)
            let viewProjection = camera.projectionMatrix * camera.viewMatrix
            let corner = viewProjection * SIMD4<Float>(screen.right, screen.top, 0, 1)
            XCTAssertEqual(corner.x / corner.w, 1, accuracy: 0.00001)
            XCTAssertEqual(corner.y / corner.w, 1, accuracy: 0.00001)
        }
    }

    func testUnsmoothedFirstSampleIsImmediateButFuturePoseWaits() throws {
        var tracker = ParallaxTracker(configuration: try .init(smoothingTime: 0))
        tracker.submit(.init(position: [0.1, 0, 0.4], timestamp: 2))
        XCTAssertEqual(tracker.sample(at: 1).status, .fallback)
        XCTAssertEqual(tracker.sample(at: 1).position, [0, 0, 0.5])
        XCTAssertEqual(tracker.sample(at: 2).position, [0.1, 0, 0.4])
        tracker.reset()
        tracker.submit(.init(position: [0.2, 0, 0.6], timestamp: 3))
        XCTAssertEqual(tracker.sample(at: 3).position, [0.2, 0, 0.6])
    }

    private func motion(angle: Float, at time: TimeInterval) -> ParallaxMotionSample {
        .init(referenceToDevice: simd_quatf(angle: angle, axis: [0, 1, 0]), timestamp: time)
    }
}
