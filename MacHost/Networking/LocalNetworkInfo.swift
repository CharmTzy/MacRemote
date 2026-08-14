import Foundation

/// Reads this Mac's primary Wi-Fi/Ethernet IPv4 address for display in the
/// Overview screen and for the "Add by IP Address" fallback. Best-effort:
/// returns `nil` if no active `en*` interface is found.
enum LocalNetworkInfo {
    static func primaryIPv4Address() -> String? {
        var resolvedAddress: String?
        var interfaceListPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaceListPointer) == 0, let firstInterface = interfaceListPointer else {
            return nil
        }
        defer { freeifaddrs(interfaceListPointer) }

        for interface in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let flags = interface.pointee.ifa_flags
            let isUpAndRunning = (flags & UInt32(IFF_UP)) != 0 && (flags & UInt32(IFF_RUNNING)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            guard isUpAndRunning, !isLoopback else { continue }

            guard let socketAddress = interface.pointee.ifa_addr, socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let interfaceName = String(cString: interface.pointee.ifa_name)
            guard interfaceName.hasPrefix("en") else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            resolvedAddress = String(cString: hostBuffer)
            break
        }

        return resolvedAddress
    }
}
