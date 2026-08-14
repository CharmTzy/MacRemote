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

    // Authentication (Phase 2) — see PROTOCOL.md for the full sequence.
    case authBegin(AuthBeginPayload)
    case authChallenge(AuthChallengePayload)
    case sessionAuthResponse(SessionAuthResponsePayload)
    case pairingConfirm(PairingConfirmPayload)
    case identityExchange(SealedPayload)
    case authResult(AuthResultPayload)
    /// Any message sent after authentication completes, sealed with the
    /// session's `SecureSession`. The plaintext inside is itself a full
    /// inner message (category + type + payload) — see `encodedInner()`.
    case secureEnvelope(SealedPayload)
}

extension ProtocolMessage {
    var category: MessageCategory {
        switch self {
        case .hello, .helloAck: return .session
        case .ping, .pong: return .heartbeat
        case .authBegin, .authChallenge, .sessionAuthResponse, .pairingConfirm, .identityExchange, .authResult, .secureEnvelope:
            return .authentication
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
        case .authBegin: return 1
        case .authChallenge: return 2
        case .sessionAuthResponse: return 3
        case .pairingConfirm: return 4
        case .identityExchange: return 5
        case .authResult: return 6
        case .secureEnvelope: return 7
        }
    }

    private func encodePayload() -> Data {
        var writer = ByteWriter()
        switch self {
        case .hello(let payload): payload.encode(into: &writer)
        case .helloAck(let payload): payload.encode(into: &writer)
        case .ping(let timestamp): writer.writeUInt64(timestamp)
        case .pong(let timestamp): writer.writeUInt64(timestamp)
        case .authBegin(let payload): payload.encode(into: &writer)
        case .authChallenge(let payload): payload.encode(into: &writer)
        case .sessionAuthResponse(let payload): payload.encode(into: &writer)
        case .pairingConfirm(let payload): payload.encode(into: &writer)
        case .identityExchange(let payload): payload.encode(into: &writer)
        case .authResult(let payload): payload.encode(into: &writer)
        case .secureEnvelope(let payload): payload.encode(into: &writer)
        }
        return writer.data
    }

    /// Category + type + payload, with no outer length prefix. This is what
    /// gets sealed as the plaintext inside a `secureEnvelope`; the envelope
    /// itself supplies the framing once decrypted.
    func encodedInner() -> Data {
        var writer = ByteWriter()
        writer.writeUInt8(category.rawValue)
        writer.writeUInt8(typeCode)
        writer.data.append(encodePayload())
        return writer.data
    }

    /// Encodes this message as a length-prefixed frame ready to send on the wire.
    /// Frame layout: `[UInt32 frameLength][UInt8 category][UInt8 type][payload]`
    /// where `frameLength` counts everything after itself.
    func encodedFrame() -> Data {
        let inner = encodedInner()
        var writer = ByteWriter()
        writer.writeUInt32(UInt32(inner.count))
        writer.data.append(inner)
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
        case .authentication:
            switch type {
            case 1: return .authBegin(try AuthBeginPayload.decode(from: &reader))
            case 2: return .authChallenge(try AuthChallengePayload.decode(from: &reader))
            case 3: return .sessionAuthResponse(try SessionAuthResponsePayload.decode(from: &reader))
            case 4: return .pairingConfirm(try PairingConfirmPayload.decode(from: &reader))
            case 5: return .identityExchange(try SealedPayload.decode(from: &reader))
            case 6: return .authResult(try AuthResultPayload.decode(from: &reader))
            case 7: return .secureEnvelope(try SealedPayload.decode(from: &reader))
            default: throw DecodeError.unknownType(category: category, type: type)
            }
        case .video, .input, .keyboard, .clipboard, .file, .system, .quality:
            throw DecodeError.unknownType(category: category, type: type)
        }
    }

    /// Decodes a message from its inner (unframed) bytes — category + type +
    /// payload, no length prefix. Counterpart to `encodedInner()`.
    static func decodeInner(_ data: Data) throws -> ProtocolMessage {
        var reader = ByteReader(data)
        let categoryByte = try reader.readUInt8()
        let typeByte = try reader.readUInt8()
        guard let category = MessageCategory(rawValue: categoryByte) else {
            throw DecodeError.unknownCategory(categoryByte)
        }
        let remaining = data.suffix(from: data.startIndex + 2)
        return try decode(category: category, type: typeByte, payload: Data(remaining))
    }
}
