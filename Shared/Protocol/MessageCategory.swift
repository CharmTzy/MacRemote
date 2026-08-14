import Foundation

/// Top-level grouping for every message the wire protocol can carry.
///
/// Categories exist so the transport layer can prioritize and route traffic
/// (e.g. input must never queue behind a file transfer) without inspecting
/// message payloads. Not every category has implemented message types yet —
/// see PROTOCOL.md for what each phase adds.
enum MessageCategory: UInt8, Sendable {
    case authentication = 1
    case session = 2
    case video = 3
    case input = 4
    case keyboard = 5
    case clipboard = 6
    case file = 7
    case system = 8
    case heartbeat = 9
    case quality = 10
}
