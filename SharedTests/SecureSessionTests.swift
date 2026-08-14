import XCTest
import Foundation
import CryptoKit

final class SecureSessionTests: XCTestCase {
    func testSealOpenRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = SecureSession(key: key)
        var receiver = SecureSession(key: key)

        let sealed = try sender.seal(Data("hello mac".utf8))
        let opened = try receiver.open(counter: sealed.counter, combined: sealed.combined)

        XCTAssertEqual(opened, Data("hello mac".utf8))
    }

    func testCounterIncreasesEachSend() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = SecureSession(key: key)

        let first = try sender.seal(Data("one".utf8))
        let second = try sender.seal(Data("two".utf8))

        XCTAssertEqual(first.counter, 1)
        XCTAssertEqual(second.counter, 2)
    }

    func testReplayedCounterIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = SecureSession(key: key)
        var receiver = SecureSession(key: key)

        let sealed = try sender.seal(Data("hello".utf8))
        _ = try receiver.open(counter: sealed.counter, combined: sealed.combined)

        XCTAssertThrowsError(try receiver.open(counter: sealed.counter, combined: sealed.combined)) { error in
            XCTAssertEqual(error as? SecureSession.SecureSessionError, .replayDetected)
        }
    }

    func testTamperedCiphertextFailsToOpen() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = SecureSession(key: key)
        var receiver = SecureSession(key: key)

        let sealed = try sender.seal(Data("hello".utf8))
        var tampered = sealed.combined
        tampered[tampered.startIndex] ^= 0xFF

        XCTAssertThrowsError(try receiver.open(counter: sealed.counter, combined: tampered))
    }

    func testWrongKeyFailsToOpen() throws {
        var sender = SecureSession(key: SymmetricKey(size: .bits256))
        var receiver = SecureSession(key: SymmetricKey(size: .bits256))

        let sealed = try sender.seal(Data("hello".utf8))
        XCTAssertThrowsError(try receiver.open(counter: sealed.counter, combined: sealed.combined))
    }
}
