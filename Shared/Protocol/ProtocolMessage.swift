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

    // Video (Phase 3) — always travels wrapped in secureEnvelope; see PROTOCOL.md.
    case videoConfig(VideoConfigPayload)
    case videoFrame(VideoFramePayload)
    case videoError(VideoErrorPayload)
    case displayList(DisplayListPayload)
    case selectDisplay(SelectDisplayPayload)

    // Input (Phase 4) — always travels wrapped in secureEnvelope, over the
    // control connection (never video — see ARCHITECTURE.md).
    case mouseMove(MouseMovePayload)
    case mouseButton(MouseButtonPayload)
    case mouseClick(MouseClickPayload)
    case mouseDragged(MouseDraggedPayload)
    case scroll(ScrollPayload)

    // Keyboard (Phase 5) — always travels wrapped in secureEnvelope, over
    // the control connection.
    case textInput(TextInputPayload)
    case specialKey(SpecialKeyPayload)

    // Quality (Phase 6 manual selection; Phase 8 adds automatic adjustment
    // on top of the same mechanism) — sent on the video connection.
    case qualityPreference(QualityPreferencePayload)
}

extension ProtocolMessage {
    var category: MessageCategory {
        switch self {
        case .hello, .helloAck: return .session
        case .ping, .pong: return .heartbeat
        case .authBegin, .authChallenge, .sessionAuthResponse, .pairingConfirm, .identityExchange, .authResult, .secureEnvelope:
            return .authentication
        case .videoConfig, .videoFrame, .videoError, .displayList, .selectDisplay:
            return .video
        case .mouseMove, .mouseButton, .mouseClick, .mouseDragged, .scroll:
            return .input
        case .textInput, .specialKey:
            return .keyboard
        case .qualityPreference:
            return .quality
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
        case .videoConfig: return 1
        case .videoFrame: return 2
        case .videoError: return 3
        case .displayList: return 4
        case .selectDisplay: return 5
        case .mouseMove: return 1
        case .mouseButton: return 2
        case .mouseClick: return 3
        case .mouseDragged: return 4
        case .scroll: return 5
        case .textInput: return 1
        case .specialKey: return 2
        case .qualityPreference: return 1
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
        case .videoConfig(let payload): payload.encode(into: &writer)
        case .videoFrame(let payload): payload.encode(into: &writer)
        case .videoError(let payload): payload.encode(into: &writer)
        case .displayList(let payload): payload.encode(into: &writer)
        case .selectDisplay(let payload): payload.encode(into: &writer)
        case .mouseMove(let payload): payload.encode(into: &writer)
        case .mouseButton(let payload): payload.encode(into: &writer)
        case .mouseClick(let payload): payload.encode(into: &writer)
        case .mouseDragged(let payload): payload.encode(into: &writer)
        case .scroll(let payload): payload.encode(into: &writer)
        case .textInput(let payload): payload.encode(into: &writer)
        case .specialKey(let payload): payload.encode(into: &writer)
        case .qualityPreference(let payload): payload.encode(into: &writer)
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
        case .video:
            switch type {
            case 1: return .videoConfig(try VideoConfigPayload.decode(from: &reader))
            case 2: return .videoFrame(try VideoFramePayload.decode(from: &reader))
            case 3: return .videoError(try VideoErrorPayload.decode(from: &reader))
            case 4: return .displayList(try DisplayListPayload.decode(from: &reader))
            case 5: return .selectDisplay(try SelectDisplayPayload.decode(from: &reader))
            default: throw DecodeError.unknownType(category: category, type: type)
            }
        case .input:
            switch type {
            case 1: return .mouseMove(try MouseMovePayload.decode(from: &reader))
            case 2: return .mouseButton(try MouseButtonPayload.decode(from: &reader))
            case 3: return .mouseClick(try MouseClickPayload.decode(from: &reader))
            case 4: return .mouseDragged(try MouseDraggedPayload.decode(from: &reader))
            case 5: return .scroll(try ScrollPayload.decode(from: &reader))
            default: throw DecodeError.unknownType(category: category, type: type)
            }
        case .keyboard:
            switch type {
            case 1: return .textInput(try TextInputPayload.decode(from: &reader))
            case 2: return .specialKey(try SpecialKeyPayload.decode(from: &reader))
            default: throw DecodeError.unknownType(category: category, type: type)
            }
        case .quality:
            switch type {
            case 1: return .qualityPreference(try QualityPreferencePayload.decode(from: &reader))
            default: throw DecodeError.unknownType(category: category, type: type)
            }
        case .clipboard, .file, .system:
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
