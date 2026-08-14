import XCTest
import Foundation

final class AuthPayloadTests: XCTestCase {
    func testAuthBeginRoundTrip() throws {
        let payload = AuthBeginPayload(ephemeralPublicKey: Data((0..<32).map { UInt8($0) }))
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try AuthBeginPayload.decode(from: &reader), payload)
    }

    func testAuthChallengeRoundTripBothModes() throws {
        for mode: AuthMode in [.pairingRequired, .sessionAuth] {
            let payload = AuthChallengePayload(
                mode: mode,
                ephemeralPublicKey: Data((0..<32).map { UInt8($0) }),
                nonce: Data((0..<16).map { UInt8($0) }),
                signature: mode == .sessionAuth ? Data((0..<64).map { UInt8($0) }) : Data()
            )
            var writer = ByteWriter()
            payload.encode(into: &writer)
            var reader = ByteReader(writer.data)
            XCTAssertEqual(try AuthChallengePayload.decode(from: &reader), payload)
        }
    }

    func testSealedPayloadRoundTrip() throws {
        let payload = SealedPayload(counter: 42, combined: Data((0..<48).map { UInt8($0) }))
        var writer = ByteWriter()
        payload.encode(into: &writer)
        var reader = ByteReader(writer.data)
        XCTAssertEqual(try SealedPayload.decode(from: &reader), payload)
    }

    func testAuthResultRoundTripWithAndWithoutReason() throws {
        for payload in [
            AuthResultPayload(accepted: true, reason: nil),
            AuthResultPayload(accepted: false, reason: "Incorrect pairing code.")
        ] {
            var writer = ByteWriter()
            payload.encode(into: &writer)
            var reader = ByteReader(writer.data)
            XCTAssertEqual(try AuthResultPayload.decode(from: &reader), payload)
        }
    }

    func testPairingIdentityPlaintextRoundTrip() throws {
        let identity = PairingIdentityPlaintext(publicKey: Data((0..<32).map { UInt8($0) }), deviceName: "Wai's iPhone", deviceModel: "iPhone16,2")
        let decoded = try PairingIdentityPlaintext.decode(from: identity.encoded())
        XCTAssertEqual(decoded.publicKey, identity.publicKey)
        XCTAssertEqual(decoded.deviceName, identity.deviceName)
        XCTAssertEqual(decoded.deviceModel, identity.deviceModel)
    }

    func testSecureEnvelopeInnerMessageRoundTrip() throws {
        let inner = ProtocolMessage.authResult(AuthResultPayload(accepted: true, reason: nil))
        let encoded = inner.encodedInner()
        let decoded = try ProtocolMessage.decodeInner(encoded)

        guard case .authResult(let payload) = decoded else {
            return XCTFail("Expected .authResult")
        }
        XCTAssertTrue(payload.accepted)
    }
}
