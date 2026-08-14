import Foundation

/// `.sessionAuth` path only: the connecting device's signature over the
/// key-agreement transcript, made with its long-term identity key. The Mac
/// verifies this against the public key recorded when this device paired.
struct SessionAuthResponsePayload: Sendable, Equatable {
    let signature: Data

    func encode(into writer: inout ByteWriter) {
        writer.writeData(signature)
    }

    static func decode(from reader: inout ByteReader) throws -> SessionAuthResponsePayload {
        SessionAuthResponsePayload(signature: try reader.readData())
    }
}
