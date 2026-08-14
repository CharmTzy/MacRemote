import Foundation
import CryptoKit

/// Seals and opens post-authentication traffic with AES-GCM, using a
/// strictly-increasing counter (authenticated as associated data, not
/// secret) for replay protection. Sending and receiving each track their
/// own counter, since the two directions are independent.
struct SecureSession {
    enum SecureSessionError: Error, Equatable {
        case replayDetected
        case invalidEnvelope
    }

    struct Sealed {
        let counter: UInt64
        let combined: Data
    }

    private let key: SymmetricKey
    private var sendCounter: UInt64 = 0
    private var lastReceivedCounter: UInt64 = 0

    init(key: SymmetricKey) {
        self.key = key
    }

    mutating func seal(_ plaintext: Data) throws -> Sealed {
        sendCounter += 1
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: Self.counterBytes(sendCounter))
        guard let combined = box.combined else { throw SecureSessionError.invalidEnvelope }
        return Sealed(counter: sendCounter, combined: combined)
    }

    mutating func open(counter: UInt64, combined: Data) throws -> Data {
        guard counter > lastReceivedCounter else {
            throw SecureSessionError.replayDetected
        }
        let box = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: Self.counterBytes(counter))
        lastReceivedCounter = counter
        return plaintext
    }

    private static func counterBytes(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }
}
