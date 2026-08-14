import Foundation
import CryptoKit
import OSLog

/// Drives the authentication phase for one incoming connection, after Hello
/// but before the connection is trusted with anything. Decides pairing vs.
/// returning-device session auth by checking the trust store, then runs
/// that path to completion.
///
/// Pure orchestration: key derivation lives in `PairingCrypto`, sealing
/// lives in `SecureSession`, trust decisions live in `TrustedDeviceStore`.
/// See PROTOCOL.md for the full message sequence this implements.
struct HostAuthenticator {
    enum Outcome {
        case authenticated(session: SecureSession)
        case rejected(reason: String)
    }

    let trustedDevices: TrustedDeviceStore
    let pairingCoordinator: PairingCoordinator

    /// `iterator` must be the connection's one and only live consumer of its
    /// event stream — `AsyncStream` doesn't support multiple independent
    /// iterators safely, so callers create it once (typically right after
    /// receiving Hello) and keep threading the same instance through the
    /// rest of the connection's lifetime, including post-auth traffic.
    func authenticate(hello: HelloPayload, transport: MessageTransport, iterator: inout AsyncStream<TransportEvent>.Iterator) async -> Outcome {
        guard let authBegin = await nextPayload(from: &iterator, as: { if case .authBegin(let p) = $0 { return p } else { return nil } }) else {
            return .rejected(reason: "The connection closed before authentication finished.")
        }
        guard let peerEphemeralKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: authBegin.ephemeralPublicKey) else {
            return .rejected(reason: "Malformed authentication data.")
        }

        let hostEphemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let hostEphemeralPublicKey = hostEphemeralPrivateKey.publicKey
        let nonce = Self.randomBytes(16)

        guard let sharedSecret = try? hostEphemeralPrivateKey.sharedSecretFromKeyAgreement(with: peerEphemeralKey) else {
            return .rejected(reason: "Couldn't establish a secure channel.")
        }

        var transcript = authBegin.ephemeralPublicKey
        transcript.append(hostEphemeralPublicKey.rawRepresentation)
        transcript.append(nonce)

        if let trusted = trustedDevices.record(for: hello.deviceID) {
            return await runSessionAuth(
                trusted: trusted,
                transcript: transcript,
                sharedSecret: sharedSecret,
                nonce: nonce,
                hostEphemeralPublicKey: hostEphemeralPublicKey,
                transport: transport,
                iterator: &iterator
            )
        } else {
            return await runPairing(
                hello: hello,
                transcript: transcript,
                sharedSecret: sharedSecret,
                nonce: nonce,
                hostEphemeralPublicKey: hostEphemeralPublicKey,
                transport: transport,
                iterator: &iterator
            )
        }
    }

    // MARK: - Session auth (returning, already-paired device)

    private func runSessionAuth(
        trusted: PairedDeviceRecord,
        transcript: Data,
        sharedSecret: SharedSecret,
        nonce: Data,
        hostEphemeralPublicKey: Curve25519.KeyAgreement.PublicKey,
        transport: MessageTransport,
        iterator: inout AsyncStream<TransportEvent>.Iterator
    ) async -> Outcome {
        let signature = (try? IdentityKeyManager.longTermPrivateKey().signature(for: transcript)) ?? Data()

        try? await transport.send(.authChallenge(AuthChallengePayload(
            mode: .sessionAuth,
            ephemeralPublicKey: hostEphemeralPublicKey.rawRepresentation,
            nonce: nonce,
            signature: signature
        )))

        guard let response = await nextPayload(from: &iterator, as: { if case .sessionAuthResponse(let p) = $0 { return p } else { return nil } }) else {
            return .rejected(reason: "The connection closed before authentication finished.")
        }

        guard let trustedPublicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: trusted.publicKey),
              trustedPublicKey.isValidSignature(response.signature, for: transcript) else {
            try? await transport.send(.authResult(AuthResultPayload(accepted: false, reason: "This device's identity couldn't be verified. Try forgetting and re-pairing it.")))
            return .rejected(reason: "Signature verification failed for \(trusted.name).")
        }

        let sessionKey = PairingCrypto.sessionKey(sharedSecret: sharedSecret, nonce: nonce)
        try? await transport.send(.authResult(AuthResultPayload(accepted: true, reason: nil)))
        return .authenticated(session: SecureSession(key: sessionKey))
    }

    // MARK: - Pairing (first-time device)

    private func runPairing(
        hello: HelloPayload,
        transcript: Data,
        sharedSecret: SharedSecret,
        nonce: Data,
        hostEphemeralPublicKey: Curve25519.KeyAgreement.PublicKey,
        transport: MessageTransport,
        iterator: inout AsyncStream<TransportEvent>.Iterator
    ) async -> Outcome {
        try? await transport.send(.authChallenge(AuthChallengePayload(
            mode: .pairingRequired,
            ephemeralPublicKey: hostEphemeralPublicKey.rawRepresentation,
            nonce: nonce,
            signature: Data()
        )))

        guard let confirm = await nextPayload(from: &iterator, as: { if case .pairingConfirm(let p) = $0 { return p } else { return nil } }) else {
            return .rejected(reason: "The connection closed before pairing finished.")
        }

        guard let code = await pairingCoordinator.codeForVerification() else {
            try? await transport.send(.authResult(AuthResultPayload(accepted: false, reason: "Incorrect pairing code.")))
            return .rejected(reason: "No active pairing code.")
        }

        let confirmKey = PairingCrypto.pairingConfirmKey(sharedSecret: sharedSecret, code: code, nonce: nonce)
        let expectedTag = PairingCrypto.confirmTag(key: confirmKey, context: "iphone-confirm", transcript: transcript)

        guard expectedTag == confirm.confirmTag else {
            await pairingCoordinator.recordFailedAttempt()
            try? await transport.send(.authResult(AuthResultPayload(accepted: false, reason: "Incorrect pairing code.")))
            return .rejected(reason: "Pairing code mismatch.")
        }

        let macConfirmTag = PairingCrypto.confirmTag(key: confirmKey, context: "mac-confirm", transcript: transcript)
        try? await transport.send(.pairingConfirm(PairingConfirmPayload(confirmTag: macConfirmTag)))

        let trafficKey = PairingCrypto.pairingTrafficKey(sharedSecret: sharedSecret, code: code, nonce: nonce)
        var session = SecureSession(key: trafficKey)

        let hostIdentity = PairingIdentityPlaintext(
            publicKey: IdentityKeyManager.longTermPublicKey.rawRepresentation,
            deviceName: DeviceIdentity.localDeviceName,
            deviceModel: DeviceIdentity.localDeviceModel
        )
        guard let sealedHostIdentity = try? session.seal(hostIdentity.encoded()) else {
            return .rejected(reason: "Couldn't seal this Mac's identity.")
        }
        try? await transport.send(.identityExchange(SealedPayload(counter: sealedHostIdentity.counter, combined: sealedHostIdentity.combined)))

        guard let peerSealedIdentity = await nextPayload(from: &iterator, as: { if case .identityExchange(let p) = $0 { return p } else { return nil } }) else {
            return .rejected(reason: "The connection closed before pairing finished.")
        }
        guard let peerIdentityData = try? session.open(counter: peerSealedIdentity.counter, combined: peerSealedIdentity.combined),
              let peerIdentity = try? PairingIdentityPlaintext.decode(from: peerIdentityData) else {
            return .rejected(reason: "Couldn't verify the other device's identity.")
        }

        let record = PairedDeviceRecord(
            id: hello.deviceID,
            name: peerIdentity.deviceName,
            model: peerIdentity.deviceModel,
            publicKey: peerIdentity.publicKey,
            pairedAt: Date()
        )
        guard (try? trustedDevices.save(record)) != nil else {
            return .rejected(reason: "Couldn't save this device's pairing record.")
        }

        await pairingCoordinator.recordSuccess()
        try? await transport.send(.authResult(AuthResultPayload(accepted: true, reason: nil)))
        Logging.pairing.info("Paired with \(peerIdentity.deviceName, privacy: .public)")
        return .authenticated(session: session)
    }

    // MARK: - Helpers

    private func nextPayload<T>(
        from iterator: inout AsyncStream<TransportEvent>.Iterator,
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

    private static func randomBytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
}
