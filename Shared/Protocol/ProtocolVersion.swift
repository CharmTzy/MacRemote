import Foundation

/// Wire protocol version. Bump when a change is not backward compatible so
/// peers can reject an incompatible session during the Hello handshake
/// instead of failing unpredictably later.
enum ProtocolVersion {
    static let current: UInt16 = 1
}
