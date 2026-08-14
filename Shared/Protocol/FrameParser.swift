import Foundation

/// Incrementally reassembles length-prefixed frames from a byte stream that
/// may arrive in arbitrary chunks (as TCP data does). Feed it every chunk
/// received from the socket; it returns zero or more complete, decoded
/// messages each time.
struct FrameParser {
    private var buffer = Data()

    /// Frames larger than this are rejected. Generous enough for a full
    /// 1080p H.264 keyframe, small enough to bound memory if a peer sends
    /// garbage.
    static let maxFrameLength = 16 * 1024 * 1024

    enum FrameError: Error {
        case frameTooLarge(Int)
    }

    mutating func feed(_ chunk: Data) throws -> [ProtocolMessage] {
        buffer.append(chunk)
        var messages: [ProtocolMessage] = []

        while true {
            guard buffer.count >= 4 else { break }
            let lengthBytes = buffer.subdata(in: buffer.startIndex..<(buffer.startIndex + 4))
            let frameLength = Int(lengthBytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)

            guard frameLength >= 2 else {
                // A well-formed frame always has at least category + type.
                buffer.removeAll()
                break
            }
            guard frameLength <= Self.maxFrameLength else {
                throw FrameError.frameTooLarge(frameLength)
            }

            let totalNeeded = 4 + frameLength
            guard buffer.count >= totalNeeded else { break }

            let frameStart = buffer.startIndex + 4
            let category = buffer[frameStart]
            let type = buffer[frameStart + 1]
            let payload = buffer.subdata(in: (frameStart + 2)..<(buffer.startIndex + totalNeeded))

            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + totalNeeded))

            guard let messageCategory = MessageCategory(rawValue: category) else {
                continue // Unknown category from a newer peer version; skip rather than fail the connection.
            }
            if let message = try? ProtocolMessage.decode(category: messageCategory, type: type, payload: payload) {
                messages.append(message)
            }
        }

        return messages
    }
}
