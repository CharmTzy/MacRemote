import Foundation

/// User-selected streaming quality. `.auto` is a fixed reasonable default
/// for now (`.balanced`'s numbers) — genuinely automatic, network-aware
/// adjustment is Phase 8 scope, built as a second layer on top of this
/// same mechanism rather than a separate one.
enum QualityProfile: String, CaseIterable, Identifiable, Sendable {
    case auto, low, balanced, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .low: return "Low"
        case .balanced: return "Balanced"
        case .high: return "High"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Adjusts to network conditions"
        case .low: return "720p, 30 fps"
        case .balanced: return "1080p, 30 fps"
        case .high: return "1080p, 60 fps"
        }
    }

    var averageBitRate: Int {
        switch self {
        case .low: return 2_000_000
        case .auto, .balanced: return 6_000_000
        case .high: return 12_000_000
        }
    }

    var frameRate: Int {
        switch self {
        case .high: return 60
        default: return 30
        }
    }

    var wireValue: UInt8 {
        switch self {
        case .auto: return 1
        case .low: return 2
        case .balanced: return 3
        case .high: return 4
        }
    }

    init?(wireValue: UInt8) {
        switch wireValue {
        case 1: self = .auto
        case 2: self = .low
        case 3: self = .balanced
        case 4: self = .high
        default: return nil
        }
    }
}
