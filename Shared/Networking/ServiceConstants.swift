import Foundation
import Network

/// Bonjour service identity and default port shared by both apps. Changing
/// `bonjourType` requires bumping `ProtocolVersion` too, since it changes
/// what discovers what.
enum ServiceConstants {
    /// Bonjour service type. Must be `_name._tcp` or `_name._udp`, max 15
    /// characters for the name portion.
    static let bonjourType = "_macremote._tcp"

    /// Default control-channel port used for "Add by IP Address". Bonjour
    /// discovery does not need this — it resolves the real port from the
    /// advertised service — but manual connections need a stable target.
    static let defaultControlPort: UInt16 = 53511

    static var defaultPort: NWEndpoint.Port {
        NWEndpoint.Port(rawValue: defaultControlPort)!
    }

    // TXT record keys advertised alongside the Bonjour service.
    enum TXTKey {
        static let deviceName = "name"
        static let modelIdentifier = "model"
        static let protocolVersion = "ver"
        static let deviceID = "id"
        static let ipv4Address = "ip"
        static let broadcastAddress = "broadcast"
        static let wakeMACAddress = "wake"
    }
}
