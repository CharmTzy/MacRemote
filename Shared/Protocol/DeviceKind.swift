import Foundation

/// Identifies which side of the connection a device is, as declared during
/// the session handshake. Used for UI labeling and for keeping the protocol
/// symmetric-but-role-aware (only a Mac ever sends video, only an iPhone
/// ever sends touch input).
enum DeviceKind: UInt8, Sendable {
    case mac = 1
    case iPhone = 2
}
