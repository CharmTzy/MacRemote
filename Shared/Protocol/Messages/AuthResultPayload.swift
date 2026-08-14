import Foundation

/// Final word on an authentication attempt, sent by the Mac (the side that
/// holds the trust records and therefore makes the accept/reject
/// decision). Terminates both the pairing path and the session-auth path —
/// the client waits for this regardless of which path it took.
struct AuthResultPayload: Sendable, Equatable {
    let accepted: Bool
    let reason: String?

    func encode(into writer: inout ByteWriter) {
        writer.writeBool(accepted)
        writer.writeString(reason ?? "")
    }

    static func decode(from reader: inout ByteReader) throws -> AuthResultPayload {
        let accepted = try reader.readBool()
        let reason = try reader.readString()
        return AuthResultPayload(accepted: accepted, reason: reason.isEmpty ? nil : reason)
    }
}
