import Foundation
import Network
import CryptoKit

/// Dials out to a Mac and drives the client side of the Hello →
/// authentication handshake (see PROTOCOL.md). One instance per connection
/// attempt — create a new one to retry.
///
/// Pairing needs a value only a person can supply (the code shown on the
/// Mac), so this can't be one linear `async` call: `connect(to:)` returns
/// `.pairingCodeNeeded` and pauses there, keeping the connection and the
/// in-progress key exchange alive, until `submitPairingCode(_:)` is called
/// with what the user typed.
actor RemoteConnection {
    struct PendingPairing {
        let macDeviceID: UUID
        let macName: String
        let macModel: String
        let sharedSecret: SharedSecret
        let nonce: Data
        let transcript: Data
    }

    enum ConnectResult {
        case authenticated(session: SecureSession, macDeviceID: UUID, macName: String, macModel: String)
        case pairingCodeNeeded
    }

    enum ConnectionError: LocalizedError {
        case rejected(String)
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .rejected(let reason): return reason
            case .connectionClosed: return "The connection closed unexpectedly."
            }
        }
    }

    private var transport: MessageTransport?
    private var iterator: AsyncStream<TransportEvent>.Iterator?
    private var pendingPairing: PendingPairing?
    private var activeSession: SecureSession?
    private let trustedDevices = TrustedDeviceStore()

    @discardableResult
    func connect(to endpoint: NWEndpoint, purpose: ChannelPurpose = .control) async throws -> ConnectResult {
        let transport = MessageTransport.connect(to: endpoint, parameters: NWParametersFactory.controlChannel())
        self.transport = transport
        let stream = await transport.events
        var iter = stream.makeAsyncIterator()

        guard await Self.waitUntilReady(&iter) else {
            throw ConnectionError.connectionClosed
        }

        let hello = HelloPayload(
            protocolVersion: ProtocolVersion.current,
            deviceID: DeviceIdentity.localDeviceID(),
            deviceName: DeviceIdentity.localDeviceName,
            deviceModel: DeviceIdentity.localDeviceModel,
            deviceKind: .iPhone,
            channelPurpose: purpose
        )
        try await transport.send(.hello(hello))

        guard let ack = await Self.nextPayload(&iter, as: { if case .helloAck(let p) = $0 { return p } else { return nil } }), ack.accepted else {
            throw ConnectionError.rejected("The Mac declined the connection.")
        }

        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        try await transport.send(.authBegin(AuthBeginPayload(ephemeralPublicKey: ephemeralPrivateKey.publicKey.rawRepresentation)))

        guard let challenge = await Self.nextPayload(&iter, as: { if case .authChallenge(let p) = $0 { return p } else { return nil } }) else {
            throw ConnectionError.connectionClosed
        }
        guard let macEphemeralPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: challenge.ephemeralPublicKey),
              let sharedSecret = try? ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: macEphemeralPublicKey) else {
            throw ConnectionError.rejected("Couldn't establish a secure channel.")
        }

        var transcript = ephemeralPrivateKey.publicKey.rawRepresentation
        transcript.append(challenge.ephemeralPublicKey)
        transcript.append(challenge.nonce)

        switch challenge.mode {
        case .sessionAuth:
            self.iterator = iter
            return try await completeSessionAuth(ack: ack, challenge: challenge, sharedSecret: sharedSecret, transcript: transcript, transport: transport)

        case .pairingRequired:
            pendingPairing = PendingPairing(
                macDeviceID: ack.deviceID,
                macName: ack.deviceName,
                macModel: ack.deviceModel,
                sharedSecret: sharedSecret,
                nonce: challenge.nonce,
                transcript: transcript
            )
            self.iterator = iter
            return .pairingCodeNeeded
        }
    }

    private func completeSessionAuth(
        ack: HelloAckPayload,
        challenge: AuthChallengePayload,
        sharedSecret: SharedSecret,
        transcript: Data,
        transport: MessageTransport
    ) async throws -> ConnectResult {
        guard var iter = iterator else { throw ConnectionError.connectionClosed }
        defer { iterator = iter }

        guard let trusted = trustedDevices.record(for: ack.deviceID),
              let trustedKey = try? Curve25519.Signing.PublicKey(rawRepresentation: trusted.publicKey),
              trustedKey.isValidSignature(challenge.signature, for: transcript) else {
            throw ConnectionError.rejected("This Mac's identity couldn't be verified. If it was recently reset, forget it and pair again.")
        }

        let signature = (try? IdentityKeyManager.longTermPrivateKey().signature(for: transcript)) ?? Data()
        try await transport.send(.sessionAuthResponse(SessionAuthResponsePayload(signature: signature)))

        guard let result = await Self.nextPayload(&iter, as: { if case .authResult(let p) = $0 { return p } else { return nil } }) else {
            throw ConnectionError.connectionClosed
        }
        guard result.accepted else {
            throw ConnectionError.rejected(result.reason ?? "Authentication failed.")
        }

        let sessionKey = PairingCrypto.sessionKey(sharedSecret: sharedSecret, nonce: challenge.nonce)
        let session = SecureSession(key: sessionKey)
        activeSession = session
        return .authenticated(session: session, macDeviceID: ack.deviceID, macName: ack.deviceName, macModel: ack.deviceModel)
    }

    func submitPairingCode(_ code: String) async throws -> ConnectResult {
        guard let transport, var iter = iterator, let pending = pendingPairing else {
            throw ConnectionError.connectionClosed
        }
        defer { iterator = iter }

        let confirmKey = PairingCrypto.pairingConfirmKey(sharedSecret: pending.sharedSecret, code: code, nonce: pending.nonce)
        let myTag = PairingCrypto.confirmTag(key: confirmKey, context: "iphone-confirm", transcript: pending.transcript)
        try await transport.send(.pairingConfirm(PairingConfirmPayload(confirmTag: myTag)))

        guard let macConfirm = await Self.nextPayload(&iter, as: { if case .pairingConfirm(let p) = $0 { return p } else { return nil } }) else {
            throw ConnectionError.connectionClosed
        }
        let expectedMacTag = PairingCrypto.confirmTag(key: confirmKey, context: "mac-confirm", transcript: pending.transcript)
        guard macConfirm.confirmTag == expectedMacTag else {
            throw ConnectionError.rejected("Incorrect pairing code.")
        }

        let trafficKey = PairingCrypto.pairingTrafficKey(sharedSecret: pending.sharedSecret, code: code, nonce: pending.nonce)
        var session = SecureSession(key: trafficKey)

        let myIdentity = PairingIdentityPlaintext(
            publicKey: IdentityKeyManager.longTermPublicKey.rawRepresentation,
            deviceName: DeviceIdentity.localDeviceName,
            deviceModel: DeviceIdentity.localDeviceModel
        )
        guard let sealedMine = try? session.seal(myIdentity.encoded()) else {
            throw ConnectionError.rejected("Couldn't seal this device's identity.")
        }
        try await transport.send(.identityExchange(SealedPayload(counter: sealedMine.counter, combined: sealedMine.combined)))

        guard let peerSealed = await Self.nextPayload(&iter, as: { if case .identityExchange(let p) = $0 { return p } else { return nil } }) else {
            throw ConnectionError.connectionClosed
        }
        guard let peerData = try? session.open(counter: peerSealed.counter, combined: peerSealed.combined),
              let peerIdentity = try? PairingIdentityPlaintext.decode(from: peerData) else {
            throw ConnectionError.rejected("Couldn't verify the Mac's identity.")
        }

        let record = PairedDeviceRecord(id: pending.macDeviceID, name: peerIdentity.deviceName, model: peerIdentity.deviceModel, publicKey: peerIdentity.publicKey, pairedAt: Date())
        try? trustedDevices.save(record)

        guard let result = await Self.nextPayload(&iter, as: { if case .authResult(let p) = $0 { return p } else { return nil } }) else {
            throw ConnectionError.connectionClosed
        }
        guard result.accepted else {
            throw ConnectionError.rejected(result.reason ?? "Pairing failed.")
        }

        pendingPairing = nil
        activeSession = session
        return .authenticated(session: session, macDeviceID: pending.macDeviceID, macName: peerIdentity.deviceName, macModel: peerIdentity.deviceModel)
    }

    /// Pulls the next authenticated message, decrypting `secureEnvelope`
    /// traffic with the session established by `connect(to:)` /
    /// `submitPairingCode(_:)`. Only meaningful after one of those returned
    /// `.authenticated`. Returns `nil` once the connection closes.
    func nextMessage() async -> ProtocolMessage? {
        guard var iter = iterator else { return nil }
        defer { iterator = iter }

        while let event = await iter.next() {
            switch event {
            case .message(let message):
                guard case .secureEnvelope(let sealed) = message, var session = activeSession else { continue }
                var decoded: ProtocolMessage?
                if let plaintext = try? session.open(counter: sealed.counter, combined: sealed.combined) {
                    decoded = try? ProtocolMessage.decodeInner(plaintext)
                }
                activeSession = session
                if let decoded { return decoded }
            case .failed, .cancelled:
                return nil
            case .ready:
                continue
            }
        }
        return nil
    }

    /// Seals and sends one message over the authenticated session. Only
    /// meaningful after `connect(to:)` / `submitPairingCode(_:)` returned
    /// `.authenticated`.
    func send(_ message: ProtocolMessage) async throws {
        guard let transport, var session = activeSession else {
            throw ConnectionError.connectionClosed
        }
        let sealed = try session.seal(message.encodedInner())
        activeSession = session
        try await transport.send(.secureEnvelope(SealedPayload(counter: sealed.counter, combined: sealed.combined)))
    }

    func close() async {
        await transport?.close()
        transport = nil
        iterator = nil
        pendingPairing = nil
        activeSession = nil
    }

    private static func waitUntilReady(_ iterator: inout AsyncStream<TransportEvent>.Iterator) async -> Bool {
        while let event = await iterator.next() {
            switch event {
            case .ready: return true
            case .failed, .cancelled: return false
            case .message: continue
            }
        }
        return false
    }

    private static func nextPayload<T>(
        _ iterator: inout AsyncStream<TransportEvent>.Iterator,
        as extract: (ProtocolMessage) -> T?
    ) async -> T? {
        while let event = await iterator.next() {
            switch event {
            case .message(let message):
                if let value = extract(message) { return value }
            case .failed, .cancelled:
                return nil
            case .ready:
                continue
            }
        }
        return nil
    }
}
