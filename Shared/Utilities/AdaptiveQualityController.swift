import Foundation

/// Decides whether `.auto` streaming quality should currently behave as
/// `.low` or `.balanced`, from a rolling window of round-trip-time
/// samples (measured over the video connection's heartbeat — see
/// PROTOCOL.md). Pure decision logic, no networking or timers, so it's
/// unit testable without a live connection.
///
/// Deliberately conservative: only two states, and no automatic path to
/// `.high` — a manual choice is what `.high` is for. This is Phase 8's
/// "automatic" layer on top of Phase 6's manual `QualityProfile`
/// selection; both call the same `VideoStreamer.applyQuality(_:)`.
struct AdaptiveQualityController {
    private static let windowSize = 5
    private static let degradeThreshold: TimeInterval = 0.15
    private static let recoverThreshold: TimeInterval = 0.05

    private var recentRoundTrips: [TimeInterval] = []
    private(set) var currentProfile: QualityProfile = .balanced

    /// Feeds one round-trip-time sample (seconds) and returns the profile
    /// that should be active now. Only changes once a full window of
    /// samples has been collected, so a single good or bad sample doesn't
    /// cause a flip.
    mutating func recordRoundTrip(_ roundTripSeconds: TimeInterval) -> QualityProfile {
        appendSample(roundTripSeconds)
        guard recentRoundTrips.count == Self.windowSize else { return currentProfile }

        let average = recentRoundTrips.reduce(0, +) / Double(recentRoundTrips.count)
        if average > Self.degradeThreshold {
            currentProfile = .low
        } else if average < Self.recoverThreshold {
            currentProfile = .balanced
        }
        return currentProfile
    }

    /// A ping that never got a reply — treated as a very bad round trip,
    /// pushing toward `.low` faster than a slow-but-present reply would.
    mutating func recordTimeout() -> QualityProfile {
        appendSample(Self.degradeThreshold + 1)
        currentProfile = .low
        return currentProfile
    }

    private mutating func appendSample(_ value: TimeInterval) {
        recentRoundTrips.append(value)
        if recentRoundTrips.count > Self.windowSize {
            recentRoundTrips.removeFirst(recentRoundTrips.count - Self.windowSize)
        }
    }
}
