import Foundation

/// Exponential backoff schedule for reconnection attempts: 2, 4, 8, 16, 30,
/// 30, ... seconds — capped so a long outage doesn't mean an ever-growing
/// wait once the network actually comes back.
enum ReconnectPolicy {
    static let maxAttempts = 6

    static func delay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(attempt)), 30)
    }
}
