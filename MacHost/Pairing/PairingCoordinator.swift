import Foundation
import Combine

/// Owns the Mac's currently-active pairing code, if any. The Mac only
/// accepts a pairing attempt while this has a live code — an iPhone trying
/// to pair when no one has opened "Pair New Device" on the Mac always
/// fails with the same generic reason as a wrong code, so the protocol
/// never reveals whether pairing mode happens to be active.
@MainActor
final class PairingCoordinator: ObservableObject {
    @Published private(set) var activeCode: String?
    @Published private(set) var expiresAt: Date?

    private var failedAttempts = 0
    private let maxFailedAttempts = 5
    private let codeLifetime: TimeInterval = 180

    /// Six digits, grouped for display as "847 291".
    var formattedCode: String? {
        guard let activeCode, activeCode.count == 6 else { return activeCode }
        let midpoint = activeCode.index(activeCode.startIndex, offsetBy: 3)
        return "\(activeCode[..<midpoint]) \(activeCode[midpoint...])"
    }

    func startPairing() {
        activeCode = String(format: "%06d", Int.random(in: 0...999_999))
        expiresAt = Date().addingTimeInterval(codeLifetime)
        failedAttempts = 0
    }

    func stopPairing() {
        activeCode = nil
        expiresAt = nil
        failedAttempts = 0
    }

    /// The code a pairing attempt must match, or `nil` if pairing isn't
    /// open, the code expired, or too many attempts already failed.
    func codeForVerification() -> String? {
        guard let activeCode, let expiresAt, expiresAt > Date(), failedAttempts < maxFailedAttempts else {
            return nil
        }
        return activeCode
    }

    func recordFailedAttempt() {
        failedAttempts += 1
        if failedAttempts >= maxFailedAttempts {
            stopPairing()
        }
    }

    func recordSuccess() {
        stopPairing()
    }
}
