import XCTest
import Foundation

final class SystemCommandPayloadTests: XCTestCase {
    func testSystemCommandRoundTripAllCases() throws {
        for command in SystemCommand.allCases {
            let payload = SystemCommandPayload(command: command)
            var writer = ByteWriter()
            payload.encode(into: &writer)
            var reader = ByteReader(writer.data)
            XCTAssertEqual(try SystemCommandPayload.decode(from: &reader), payload)
        }
    }

    func testSystemCommandRoutesToSystemCategory() {
        XCTAssertEqual(ProtocolMessage.systemCommand(SystemCommandPayload(command: .lockScreen)).category, .system)
    }

    func testOnlyRestartAndShutdownRequireConfirmation() {
        let confirmed = SystemCommand.allCases.filter(\.requiresConfirmation)
        XCTAssertEqual(Set(confirmed), [.restart, .shutdown])
    }

    func testRawValuesAreUnique() {
        let values = Set(SystemCommand.allCases.map(\.rawValue))
        XCTAssertEqual(values.count, SystemCommand.allCases.count)
    }
}
