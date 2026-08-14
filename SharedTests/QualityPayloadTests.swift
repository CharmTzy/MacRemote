import XCTest
import Foundation

final class QualityPayloadTests: XCTestCase {
    func testQualityPreferenceRoundTripAllProfiles() throws {
        for profile in QualityProfile.allCases {
            let payload = QualityPreferencePayload(profile: profile)
            var writer = ByteWriter()
            payload.encode(into: &writer)
            var reader = ByteReader(writer.data)
            XCTAssertEqual(try QualityPreferencePayload.decode(from: &reader), payload)
        }
    }

    func testQualityPreferenceRoutesToQualityCategory() {
        let message = ProtocolMessage.qualityPreference(QualityPreferencePayload(profile: .high))
        XCTAssertEqual(message.category, .quality)
    }

    func testWireValuesAreStableAndUnique() {
        let wireValues = Set(QualityProfile.allCases.map(\.wireValue))
        XCTAssertEqual(wireValues.count, QualityProfile.allCases.count)
    }
}
