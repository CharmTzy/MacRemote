import Foundation
import Network

/// Builds the `NWParameters` used for the control connection. Centralized so
/// every place that opens a control connection (host listener, client dial,
/// manual IP connect) agrees on transport settings.
enum NWParametersFactory {
    /// TCP with Nagle's algorithm disabled. Control/input messages are small
    /// and latency-sensitive, so we trade a little bandwidth efficiency for
    /// not waiting on the Nagle/delayed-ACK interaction.
    static func controlChannel() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = 8

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.includePeerToPeer = false
        return parameters
    }
}
