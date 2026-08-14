import Foundation

/// An iPhone currently (or previously, this launch) connected to this Mac,
/// as tracked by the host. Session-scoped — persisted pairing/trust records
/// arrive in Phase 2 as a separate `PairedDevice` model.
struct ConnectedPeer: Identifiable, Equatable {
    let id: UUID
    let name: String
    let model: String
    let connectedAt: Date
    var state: ConnectionState
}
