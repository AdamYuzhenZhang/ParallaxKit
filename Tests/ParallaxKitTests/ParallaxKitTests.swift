import XCTest
import simd
@testable import ParallaxKit

final class ParallaxKitTests: XCTestCase {
    func testScreenCornersRemainRegisteredForMovingViewer() throws {
        let screen = try ParallaxScreen(width: 0.07, height: 0.15)
        for viewer: SIMD3<Float> in [[0, 0, 0.5], [0.12, -0.08, 0.3], [-0.1, 0.07, 0.8]] {
            let camera = try ParallaxProjection.camera(viewer: viewer, screen: screen)
            let viewProjection = camera.projectionMatrix * camera.viewMatrix
            for (point, expected): (SIMD3<Float>, SIMD2<Float>) in [
                ([screen.left, screen.bottom, 0], [-1, -1]),
                ([screen.right, screen.top, 0], [1, 1]),
                ([0, 0, 0], [0, 0]),
            ] {
                let p = viewProjection * SIMD4(point, 1)
                XCTAssertEqual(p.x / p.w, expected.x, accuracy: 0.00001)
                XCTAssertEqual(p.y / p.w, expected.y, accuracy: 0.00001)
            }
        }
    }

    func testReverseDepthAndParallaxDirection() throws {
        let screen = try ParallaxScreen(width: 0.07, height: 0.15)
        let camera = try ParallaxProjection.camera(viewer: [0.05, 0, 0.5], screen: screen, near: 0.01, far: 10)
        for (z, expected): (Float, Float) in [(-0.01, 1), (-10, 0)] {
            let p = camera.projectionMatrix * SIMD4<Float>(0, 0, z, 1)
            XCTAssertEqual(p.z / p.w, expected, accuracy: 0.00001)
        }
        let viewProjection = camera.projectionMatrix * camera.viewMatrix
        let behind = viewProjection * SIMD4<Float>(0, 0, -0.1, 1)
        let inFront = viewProjection * SIMD4<Float>(0, 0, 0.1, 1)
        XCTAssertGreaterThan(behind.x / behind.w, 0)
        XCTAssertLessThan(inFront.x / inFront.w, 0)
    }

    func testRejectsDegenerateGeometry() throws {
        XCTAssertThrowsError(try ParallaxScreen(width: 0, height: 0.1))
        XCTAssertThrowsError(try ParallaxScreen(width: .nan, height: 0.1))
        XCTAssertThrowsError(try ParallaxScreen(left: -.greatestFiniteMagnitude, right: .greatestFiniteMagnitude, bottom: -0.1, top: 0.1))
        let screen = try ParallaxScreen(width: 0.07, height: 0.15)
        XCTAssertThrowsError(try ParallaxProjection.camera(viewer: [0, 0, 0], screen: screen))
        XCTAssertThrowsError(try ParallaxProjection.camera(viewer: [0, 0, -0.5], screen: screen))
        XCTAssertThrowsError(try ParallaxProjection.camera(viewer: [.nan, 0, 0.5], screen: screen))
        XCTAssertThrowsError(try ParallaxProjection.camera(viewer: [0, 0, 0.5], screen: screen, near: 1, far: 0.5))
    }

    func testFilterIsIndependentOfRenderCadenceAcrossTimeout() throws {
        let configuration = try ParallaxTrackingConfiguration()
        func result(step: Double) -> SIMD3<Float> {
            var tracker = ParallaxTracker(configuration: configuration)
            _ = tracker.sample(at: 0)
            tracker.submit(.init(position: [0.1, -0.05, 0.4], timestamp: 0))
            var time = step
            while time < 1 {
                _ = tracker.sample(at: time)
                time += step
            }
            let result = tracker.sample(at: 1)
            XCTAssertEqual(result.status, .fallback)
            return result.position
        }
        XCTAssertLessThan(simd_distance(result(step: 1 / 30), result(step: 1 / 120)), 0.00001)
        XCTAssertLessThan(simd_distance(result(step: 1), result(step: 1 / 120)), 0.00001)
    }

    func testInvalidMeasurementsAndReset() throws {
        var tracker = ParallaxTracker(configuration: try .init())
        _ = tracker.sample(at: 1)
        XCTAssertTrue(tracker.submit(.init(position: [0.1, 0, 0.4], timestamp: 1)))
        XCTAssertFalse(tracker.submit(.init(position: [0, 0, 0.4], timestamp: 0.9)))
        XCTAssertFalse(tracker.submit(.init(position: [.nan, 0, 0.4], timestamp: 2)))
        XCTAssertEqual(tracker.sample(at: 1.1).status, .tracking)
        tracker.invalidate()
        XCTAssertEqual(tracker.sample(at: 1.2).status, .fallback)
        tracker.reset()
        XCTAssertEqual(tracker.sample(at: 3).position, [0, 0, 0.5])
        XCTAssertThrowsError(try ParallaxTrackingConfiguration(smoothingTime: -1))
    }
}
