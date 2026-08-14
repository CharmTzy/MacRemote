import XCTest
import Foundation

final class FileTransferPayloadTests: XCTestCase {
    func testFileOfferRoundTrip() throws {
        let payload = FileOfferPayload(transferID: UUID(), filename: "vacation.jpg", fileSize: 4_200_000)
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try FileOfferPayload.decode(from: &reader), payload)
    }

    func testFileChunkRoundTripWithBinaryData() throws {
        let payload = FileChunkPayload(transferID: UUID(), offset: 262_144, data: Data((0..<1024).map { UInt8($0 % 256) }))
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try FileChunkPayload.decode(from: &reader), payload)
    }

    func testFileCompleteRoundTrip() throws {
        let payload = FileCompletePayload(transferID: UUID())
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try FileCompletePayload.decode(from: &reader), payload)
    }

    func testFileMessagesRouteToFileCategory() {
        let id = UUID()
        let messages: [ProtocolMessage] = [
            .fileOffer(FileOfferPayload(transferID: id, filename: "a", fileSize: 1)),
            .fileChunk(FileChunkPayload(transferID: id, offset: 0, data: Data())),
            .fileComplete(FileCompletePayload(transferID: id))
        ]
        for message in messages {
            XCTAssertEqual(message.category, .file)
        }
    }
}
