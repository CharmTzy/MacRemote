import Foundation

/// Every message that can travel over a `MessageTransport`.
///
/// New cases are added phase by phase (see PROTOCOL.md); this is
/// deliberately not a giant enum written up front for categories that have
/// no implementation behind them yet.
enum ProtocolMessage: Sendable {
    case hello(HelloPayload)
    case helloAck(HelloAckPayload)
    case ping(UInt64)
    case pong(UInt64)
}

extension ProtocolMessage {
    var category: MessageCategory {
        switch self {
        case .hello, .helloAck: return .session
        case .ping, .pong: return .heartbeat
        }
    }

    /// Type discriminator, unique within a category. Kept separate from the
    /// category byte so a category's message set can grow independently.
    private var typeCode: UInt8 {
        switch self {
        case .hello: return 1
        case .helloAck: return 2
        case .ping: return 1
        case .pong: return 2
        }
    }

    private func encodePayload() -> Data {
        var writer = ByteWriter()
        switch self {
        case .hello(let payload): payload.encode(into: &writer)
        case .helloAck(let payload): payload.encode(into: &writer)
        case .ping(let timestamp): writer.writeUInt64(timestamp)
        case .pong(let timestamp): writer.writeUInt64(timestamp)
        }
        return writer.data
    }

    /// Encodes this message as a length-prefixed frame ready to send on the wire.
    /// Frame layout: `[UInt32 frameLength][UInt8 category][UInt8 type][payload]`
    /// where `frameLength` counts everything after itself.
    func encodedFrame() -> Data {
        let payload = encodePayload()
        var writer = ByteWriter()
        let frameLength = UInt32(2 + payload.count)
        writer.writeUInt32(frameLength)
        writer.writeUInt8(category.rawValue)
        writer.writeUInt8(typeCode)
        writer.data.append(payload)
        return writer.data
    }

    enum DecodeError: Error {
        case unknownCategory(UInt8)
        case unknownType(category: MessageCategory, type: UInt8)
    }

    static func decode(category: MessageCategory, type: UInt8, payload: Data) throws -> ProtocolMessage {
        var reader = ByteReader(payload)
        switch category {
        case .session:
            switch type {
            case 1: return .hello(try HelloPayload.decode(from: &reader))
            case 2: return .helloAck(try HelloAckPayload.decode(from: &reader))
            default: throw DecodeError.unknownType(category: category, type: type)
            }
        case .heartbeat:
            switch type {
            case 1: return .ping(try reader.readUInt64())
            case 2: return .pong(try reader.readUInt64())
            default: throw DecodeError.unknownType(category: category, type: type)
            }
        case .authentication, .video, .input, .keyboard, .clipboard, .file, .system, .quality:
            throw DecodeError.unknownType(category: category, type: type)
        }
    }
}
