import XCTest
import simd
@testable import ParallaxKit

final class ParallaxMotionTests: XCTestCase {
    private let identity = simd_quatf(angle: 0, axis: [0, 0, 1])

    func testAnyInitialHoldingAngleIsNeutralAndRelativeTiltHasSameEffect() throws {
        let config = try ParallaxMotionConfiguration(sensitivity: [1, 1], recenterTime: nil, smoothingTime: 0)
        let tilt = simd_quatf(angle: -0.12, axis: [0, 1, 0])
        for baseline in [identity, simd_quatf(angle: 1.4, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))] {
            var response = ParallaxMotionResponse(configuration: config)
            XCTAssertEqual(response.submit(sample(baseline, 0))?.position, config.neutralPosition)
            let pose = try XCTUnwrap(response.submit(sample(tilt * baseline, 0.1)))
            // Passive device rotation about +Y moves a stationary virtual eye
            // toward -X in the current screen frame; Z stays constant.
            XCTAssertEqual(pose.position.x, -0.5 * tan(0.12), accuracy: 0.00001)
            XCTAssertEqual(pose.position.y, 0, accuracy: 0.00001)
            XCTAssertEqual(pose.position.z, 0.5)
        }
    }

    func testRollDoesNotMoveEyeAndInterfaceAxesMapExplicitly() throws {
        let config = try ParallaxMotionConfiguration(sensitivity: [1, 1], recenterTime: nil, smoothingTime: 0)
        for (orientation, expected): (ParallaxDisplayOrientation, SIMD2<Float>) in [
            (.portrait, [1, 0]), (.portraitUpsideDown, [-1, 0]),
            (.landscapeLeft, [0, -1]), (.landscapeRight, [0, 1]),
        ] {
            var response = ParallaxMotionResponse(configuration: config)
            _ = response.submit(sample(identity, 0), orientation: orientation)
            let pose = try XCTUnwrap(response.submit(sample(simd_quatf(angle: 0.1, axis: [0, 1, 0]), 0.1), orientation: orientation))
            XCTAssertEqual(pose.position.x, expected.x * 0.5 * tan(0.1), accuracy: 0.00001)
            XCTAssertEqual(pose.position.y, expected.y * 0.5 * tan(0.1), accuracy: 0.00001)
        }
        var response = ParallaxMotionResponse(configuration: config)
        _ = response.submit(sample(identity, 0))
        let roll = try XCTUnwrap(response.submit(sample(simd_quatf(angle: 1.3, axis: [0, 0, 1]), 0.1)))
        XCTAssertEqual(roll.position, config.neutralPosition)
    }

    func testHeldTiltRecentersAndNewMovementStillResponds() throws {
        let config = try ParallaxMotionConfiguration(recenterTime: 0.35, smoothingTime: 0.04)
        var response = ParallaxMotionResponse(configuration: config)
        _ = response.submit(sample(identity, 0))
        let held = simd_quatf(angle: 0.2, axis: [0, 1, 0])
        var maximumX: Float = 0
        var end = config.neutralPosition
        for i in 1...180 {
            end = try XCTUnwrap(response.submit(sample(held, Double(i) / 60))).position
            maximumX = max(maximumX, end.x)
        }
        XCTAssertGreaterThan(maximumX, 0.025)
        XCTAssertLessThan(abs(end.x), 0.0001)
        let movedAgain = simd_quatf(angle: 0.35, axis: [0, 1, 0])
        for i in 181...187 {
            end = try XCTUnwrap(response.submit(sample(movedAgain, Double(i) / 60))).position
        }
        XCTAssertGreaterThan(end.x, 0.02)
    }

    func testDisablingRecenteringHoldsTiltAndResetStartsAtNewPose() throws {
        let config = try ParallaxMotionConfiguration(recenterTime: nil, smoothingTime: 0)
        var response = ParallaxMotionResponse(configuration: config)
        _ = response.submit(sample(identity, 0))
        let held = simd_quatf(angle: 0.2, axis: [0, 1, 0])
        let initial = try XCTUnwrap(response.submit(sample(held, 0.1)))
        var final = initial
        for i in 2...100 { final = try XCTUnwrap(response.submit(sample(held, Double(i) / 10))) }
        XCTAssertEqual(initial.position, final.position)
        response.reset()
        XCTAssertEqual(response.submit(sample(held, 11))?.position, config.neutralPosition)
    }

    func testQuaternionSignAndAngleWrapAreContinuous() throws {
        let config = try ParallaxMotionConfiguration(sensitivity: [1, 1], recenterTime: 1, smoothingTime: 0)
        var a = ParallaxMotionResponse(configuration: config)
        var b = ParallaxMotionResponse(configuration: config)
        let baseline = simd_quatf(angle: .pi - 0.01, axis: [0, 1, 0])
        _ = a.submit(sample(baseline, 0))
        _ = b.submit(sample(baseline, 0))
        let wrapped = simd_quatf(angle: -.pi + 0.01, axis: [0, 1, 0])
        let positive = try XCTUnwrap(a.submit(sample(wrapped, 0.01)))
        let negative = try XCTUnwrap(b.submit(sample(simd_quatf(vector: -wrapped.vector), 0.01)))
        XCTAssertLessThan(simd_distance(positive.position, negative.position), 0.00001)
        XCTAssertGreaterThan(positive.position.x, 0)
        XCTAssertLessThan(positive.position.x, 0.011)
    }

    func testLimitsSensitivityAndInvalidSamples() throws {
        let config = try ParallaxMotionConfiguration(
            sensitivity: [-2, 0], maximumTilt: [0.1, 0.1], maximumOffset: [0.02, 0.02],
            recenterTime: nil, smoothingTime: 0
        )
        var response = ParallaxMotionResponse(configuration: config)
        _ = response.submit(sample(identity, 1))
        let tilted = simd_quatf(angle: 0.8, axis: simd_normalize(SIMD3<Float>(1, 1, 0)))
        let pose = try XCTUnwrap(response.submit(sample(tilted, 1.1)))
        XCTAssertEqual(pose.position.x, -0.02, accuracy: 0.00001)
        XCTAssertEqual(pose.position.y, 0)
        XCTAssertNil(response.submit(sample(identity, 1.1)))
        XCTAssertNil(response.submit(sample(identity, 1.0)))
        XCTAssertNil(response.submit(sample(identity, .nan)))
        XCTAssertNil(response.submit(sample(simd_quatf(vector: .zero), 1.2)))
        XCTAssertNil(response.submit(sample(simd_quatf(vector: [.nan, 0, 0, 1]), 1.2)))
        XCTAssertEqual(response.submit(sample(tilted, 1.2))?.position, pose.position)
    }

    func testInterruptionsAndInterfaceChangesEstablishFreshNeutral() throws {
        let config = try ParallaxMotionConfiguration(recenterTime: nil, smoothingTime: 0)
        var response = ParallaxMotionResponse(configuration: config)
        _ = response.submit(sample(identity, 0))
        let tilt = simd_quatf(angle: 0.2, axis: [0, 1, 0])
        XCTAssertGreaterThan(try XCTUnwrap(response.submit(sample(tilt, 0.1))).position.x, 0.01)
        XCTAssertEqual(response.submit(sample(tilt, 2))?.position, config.neutralPosition)
        XCTAssertEqual(response.submit(sample(identity, 2.1), orientation: .landscapeLeft)?.position, config.neutralPosition)
    }

    func testResponseIsConsistentAcrossSamplingRates() throws {
        let config = try ParallaxMotionConfiguration(recenterTime: 0.7, smoothingTime: 0.06)
        let held = simd_quatf(angle: 0.25, axis: [0, 1, 0])
        func run(hz: Int) throws -> SIMD3<Float> {
            var response = ParallaxMotionResponse(configuration: config)
            _ = response.submit(sample(identity, 0))
            var result = config.neutralPosition
            for i in 1...hz {
                result = try XCTUnwrap(response.submit(sample(held, Double(i) / Double(hz)))).position
            }
            return result
        }
        XCTAssertLessThan(simd_distance(try run(hz: 30), try run(hz: 120)), 0.0002)
        XCTAssertLessThan(simd_distance(try run(hz: 60), try run(hz: 120)), 0.0002)
    }

    func testIMUPosesPreserveScreenPlaneThroughSameProjectionAndExpire() throws {
        var response = ParallaxMotionResponse(configuration: try .init(recenterTime: nil, smoothingTime: 0))
        _ = response.submit(sample(identity, 0))
        let pose = try XCTUnwrap(response.submit(sample(simd_quatf(angle: 0.2, axis: [0, 1, 0]), 0.1)))
        let screen = try ParallaxScreen(width: 0.07, height: 0.15)
        let camera = try ParallaxProjection.camera(viewer: pose.position, screen: screen)
        let viewProjection = camera.projectionMatrix * camera.viewMatrix
        for (point, expected): (SIMD3<Float>, SIMD2<Float>) in [
            ([screen.left, screen.bottom, 0], [-1, -1]),
            ([screen.right, screen.top, 0], [1, 1]), ([0, 0, 0], [0, 0]),
        ] {
            let clip = viewProjection * SIMD4(point, 1)
            XCTAssertEqual(clip.x / clip.w, expected.x, accuracy: 0.00001)
            XCTAssertEqual(clip.y / clip.w, expected.y, accuracy: 0.00001)
        }
        var tracker = ParallaxTracker(configuration: try .init(smoothingTime: 0))
        _ = tracker.sample(at: 0)
        tracker.submit(pose)
        XCTAssertEqual(tracker.sample(at: 0.2).status, .tracking)
        let expired = tracker.sample(at: 3)
        XCTAssertEqual(expired.status, .fallback)
        XCTAssertLessThan(simd_distance(expired.position, [0, 0, 0.5]), 0.0001)
    }

    func testInvalidConfiguration() {
        XCTAssertThrowsError(try ParallaxMotionConfiguration(viewerDistance: .nan))
        XCTAssertThrowsError(try ParallaxMotionConfiguration(viewerDistance: 0))
        XCTAssertThrowsError(try ParallaxMotionConfiguration(sensitivity: [.infinity, 1]))
        XCTAssertThrowsError(try ParallaxMotionConfiguration(maximumTilt: [.pi, 0.1]))
        XCTAssertThrowsError(try ParallaxMotionConfiguration(maximumOffset: [-1, 0]))
        XCTAssertThrowsError(try ParallaxMotionConfiguration(recenterTime: 0))
        XCTAssertThrowsError(try ParallaxMotionConfiguration(smoothingTime: -1))
        XCTAssertThrowsError(try ParallaxMotionConfiguration(maximumSampleGap: 0))
    }

    private func sample(_ attitude: simd_quatf, _ time: TimeInterval) -> ParallaxMotionSample {
        .init(referenceToDevice: attitude, timestamp: time)
    }
}
