import XCTest
import Foundation
import CryptoKit

final class PairingCryptoTests: XCTestCase {
    func testBothSidesDeriveSameConfirmKeyWithMatchingCode() throws {
        let alicePrivate = Curve25519.KeyAgreement.PrivateKey()
        let bobPrivate = Curve25519.KeyAgreement.PrivateKey()
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let code = "847291"

        let aliceSecret = try alicePrivate.sharedSecretFromKeyAgreement(with: bobPrivate.publicKey)
        let bobSecret = try bobPrivate.sharedSecretFromKeyAgreement(with: alicePrivate.publicKey)

        let aliceKey = PairingCrypto.pairingConfirmKey(sharedSecret: aliceSecret, code: code, nonce: nonce)
        let bobKey = PairingCrypto.pairingConfirmKey(sharedSecret: bobSecret, code: code, nonce: nonce)

        let transcript = Data("transcript-bytes".utf8)
        let aliceTag = PairingCrypto.confirmTag(key: aliceKey, context: "iphone-confirm", transcript: transcript)
        let bobTag = PairingCrypto.confirmTag(key: bobKey, context: "iphone-confirm", transcript: transcript)

        XCTAssertEqual(aliceTag, bobTag)
    }

    func testMismatchedCodeProducesDifferentTag() throws {
        let alicePrivate = Curve25519.KeyAgreement.PrivateKey()
        let bobPrivate = Curve25519.KeyAgreement.PrivateKey()
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

        let aliceSecret = try alicePrivate.sharedSecretFromKeyAgreement(with: bobPrivate.publicKey)
        let bobSecret = try bobPrivate.sharedSecretFromKeyAgreement(with: alicePrivate.publicKey)

        let aliceKey = PairingCrypto.pairingConfirmKey(sharedSecret: aliceSecret, code: "111111", nonce: nonce)
        let bobKey = PairingCrypto.pairingConfirmKey(sharedSecret: bobSecret, code: "222222", nonce: nonce)

        let transcript = Data("transcript-bytes".utf8)
        let aliceTag = PairingCrypto.confirmTag(key: aliceKey, context: "iphone-confirm", transcript: transcript)
        let bobTag = PairingCrypto.confirmTag(key: bobKey, context: "iphone-confirm", transcript: transcript)

        XCTAssertNotEqual(aliceTag, bobTag)
    }

    func testDirectionalContextsProduceDifferentTags() {
        let key = SymmetricKey(size: .bits256)
        let transcript = Data("transcript-bytes".utf8)
        let iphoneTag = PairingCrypto.confirmTag(key: key, context: "iphone-confirm", transcript: transcript)
        let macTag = PairingCrypto.confirmTag(key: key, context: "mac-confirm", transcript: transcript)
        XCTAssertNotEqual(iphoneTag, macTag)
    }

    func testTrafficKeyDiffersFromConfirmKey() throws {
        let alicePrivate = Curve25519.KeyAgreement.PrivateKey()
        let bobPrivate = Curve25519.KeyAgreement.PrivateKey()
        let nonce = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let secret = try alicePrivate.sharedSecretFromKeyAgreement(with: bobPrivate.publicKey)

        let confirmKey = PairingCrypto.pairingConfirmKey(sharedSecret: secret, code: "847291", nonce: nonce)
        let trafficKey = PairingCrypto.pairingTrafficKey(sharedSecret: secret, code: "847291", nonce: nonce)

        XCTAssertNotEqual(confirmKey.withUnsafeBytes { Data($0) }, trafficKey.withUnsafeBytes { Data($0) })
    }
}
