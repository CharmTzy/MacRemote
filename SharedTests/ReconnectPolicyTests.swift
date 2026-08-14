import XCTest
import Foundation

final class ReconnectPolicyTests: XCTestCase {
    func testDelayGrowsExponentially() {
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 1), 2)
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 2), 4)
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 3), 8)
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 4), 16)
    }

    func testDelayCapsAtThirtySeconds() {
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 5), 30)
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 10), 30)
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 100), 30)
    }
}
