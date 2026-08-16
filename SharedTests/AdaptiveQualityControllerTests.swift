import XCTest
import Foundation

final class AdaptiveQualityControllerTests: XCTestCase {
    func testStartsAtBalanced() {
        let controller = AdaptiveQualityController()
        XCTAssertEqual(controller.currentProfile, .balanced)
    }

    func testDoesNotChangeBeforeWindowFills() {
        var controller = AdaptiveQualityController()
        for _ in 0..<4 {
            XCTAssertEqual(controller.recordRoundTrip(0.5), .balanced)
        }
    }

    func testSustainedSlowRoundTripsDegradeToLow() {
        var controller = AdaptiveQualityController()
        var result: QualityProfile = .balanced
        for _ in 0..<5 {
            result = controller.recordRoundTrip(0.3)
        }
        XCTAssertEqual(result, .low)
    }

    func testTimeoutForcesLowImmediatelyOnWindowFill() {
        var controller = AdaptiveQualityController()
        var result: QualityProfile = .balanced
        for _ in 0..<5 {
            result = controller.recordTimeout()
        }
        XCTAssertEqual(result, .low)
    }

    func testRecoversToBalancedAfterSustainedFastRoundTrips() {
        var controller = AdaptiveQualityController()
        for _ in 0..<5 {
            _ = controller.recordRoundTrip(0.3)
        }
        XCTAssertEqual(controller.currentProfile, .low)

        var result: QualityProfile = .low
        for _ in 0..<5 {
            result = controller.recordRoundTrip(0.02)
        }
        XCTAssertEqual(result, .balanced)
    }

    func testModeratePingsNeitherDegradeNorRecover() {
        var controller = AdaptiveQualityController()
        var result: QualityProfile = .balanced
        for _ in 0..<5 {
            result = controller.recordRoundTrip(0.08)
        }
        XCTAssertEqual(result, .balanced)
    }
}
