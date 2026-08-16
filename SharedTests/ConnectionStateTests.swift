import XCTest
import Foundation

final class ConnectionStateTests: XCTestCase {
    func testEveryStateHasANonEmptyLabel() {
        let states: [ConnectionState] = [.searching, .available, .connecting, .connected, .offline, .authenticationFailed, .reconnecting]
        for state in states {
            XCTAssertFalse(state.label.isEmpty, "\(state) has an empty label")
        }
    }

    func testLabelsAreAllDistinct() {
        let states: [ConnectionState] = [.searching, .available, .connecting, .connected, .offline, .authenticationFailed, .reconnecting]
        let labels = Set(states.map(\.label))
        XCTAssertEqual(labels.count, states.count, "Two states share a label, which would look identical in the UI")
    }
}
