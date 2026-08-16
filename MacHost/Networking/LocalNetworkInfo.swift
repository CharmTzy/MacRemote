import Foundation
import Darwin

/// Reads this Mac's primary Wi-Fi/Ethernet IPv4 address for display in the
/// Overview screen and for the "Add by IP Address" fallback. Best-effort:
/// returns `nil` if no active `en*` interface is found.
enum LocalNetworkInfo {
    struct InterfaceDetails: Equatable {
        let name: String
        let ipv4Address: String
        let broadcastAddress: String?
        let macAddress: String?
    }

    static func primaryIPv4Address() -> String? {
        primaryInterface()?.ipv4Address
    }

    static func primaryInterface() -> InterfaceDetails? {
        var interfaceListPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaceListPointer) == 0, let firstInterface = interfaceListPointer else {
            return nil
        }
        defer { freeifaddrs(interfaceListPointer) }

        let interfaces = Array(sequence(first: firstInterface, next: { $0.pointee.ifa_next }))
        guard let ipv4Interface = interfaces.first(where: { interface in
            let flags = interface.pointee.ifa_flags
            let isUpAndRunning = (flags & UInt32(IFF_UP)) != 0 && (flags & UInt32(IFF_RUNNING)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            guard isUpAndRunning, !isLoopback,
                  let socketAddress = interface.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else { return false }
            let interfaceName = String(cString: interface.pointee.ifa_name)
            return interfaceName.hasPrefix("en")
        }), let socketAddress = ipv4Interface.pointee.ifa_addr,
              let ipv4Address = numericHost(for: socketAddress) else { return nil }

        let interfaceName = String(cString: ipv4Interface.pointee.ifa_name)
        let broadcastAddress = Optional(ipv4Interface.pointee.ifa_dstaddr).flatMap {
            numericHost(for: $0)
        }
        let macAddress = interfaces.first(where: { interface in
            String(cString: interface.pointee.ifa_name) == interfaceName &&
                interface.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)
        }).flatMap { hardwareAddress(for: $0.pointee.ifa_addr) }

        return InterfaceDetails(
            name: interfaceName,
            ipv4Address: ipv4Address,
            broadcastAddress: broadcastAddress,
            macAddress: macAddress
        )
    }

    private static func numericHost(for address: UnsafePointer<sockaddr>) -> String? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            address,
            socklen_t(address.pointee.sa_len),
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        ) == 0 else { return nil }
        return String(cString: hostBuffer)
    }

    private static func hardwareAddress(for address: UnsafePointer<sockaddr>?) -> String? {
        guard let address else { return nil }
        let linkAddress = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_dl.self)
        let nameLength = Int(linkAddress.pointee.sdl_nlen)
        let addressLength = Int(linkAddress.pointee.sdl_alen)
        guard addressLength == 6 else { return nil }

        let bytes = withUnsafeBytes(of: linkAddress.pointee.sdl_data) { rawBuffer in
            Array(rawBuffer.dropFirst(nameLength).prefix(addressLength))
        }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}
