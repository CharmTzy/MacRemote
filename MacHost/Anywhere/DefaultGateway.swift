import Foundation
import Darwin

/// Finds the IPv4 default gateway by walking the kernel route table —
/// the address our NAT-PMP/PCP requests and (usually) the UPnP device
/// live at. Best-effort: returns nil if the table can't be read or no
/// default gateway route exists.
enum DefaultGateway {
    static func ipv4Gateway() -> String? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = Data(count: length)
        let readResult = buffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
            var size = length
            return sysctl(&mib, u_int(mib.count), rawBuffer.baseAddress, &size, nil, 0)
        }
        guard readResult == 0 else { return nil }

        let headerSize = MemoryLayout<rt_msghdr>.stride
        var offset = 0
        while offset + headerSize <= buffer.count {
            let message: rt_msghdr = buffer.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
            }
            let messageLength = Int(message.rtm_msglen)
            guard message.rtm_version == UInt8(RTM_VERSION),
                  messageLength >= headerSize,
                  offset + messageLength <= buffer.count else { break }

            if isDefaultGatewayRoute(message) {
                if let gateway = parseGateway(buffer, headerEnd: offset + headerSize,
                                              addressFlags: Int(message.rtm_addrs)) {
                    return gateway
                }
            }
            offset += messageLength
        }
        return nil
    }

    /// True only for the default route: gateway-flagged with destination
    /// 0.0.0.0. Subnet routes (`10.8.0.0/24` over a VPN, say) are also
    /// RTF_GATEWAY entries and must not match.
    private static func isDefaultGatewayRoute(_ message: rt_msghdr) -> Bool {
        let flags = Int(message.rtm_flags)
        guard flags & Int(RTF_GATEWAY) != 0 else { return false }
        guard Int(message.rtm_addrs) & Int(RTA_DST) != 0,
              Int(message.rtm_addrs) & Int(RTA_GATEWAY) != 0 else {
            return false
        }
        return true
    }

    /// Walks the sockaddr array that follows an `rt_msghdr`, in the fixed
    /// order defined by the bits of `rtm_addrs`:
    /// DST, GATEWAY, NETMASK, GENMASK, IFP, IFA, AUTHOR, BRD. Returns the
    /// gateway only when the destination is 0.0.0.0 (the default route).
    private static func parseGateway(_ buffer: Data, headerEnd: Int, addressFlags: Int) -> String? {
        func roundUp(_ value: Int) -> Int { (value + 3) & ~3 }

        var cursor = headerEnd
        var sawDefaultDestination = false
        for bit in 0..<8 where addressFlags & (1 << bit) != 0 {
            guard cursor < buffer.count else { return nil }
            let saLen = Int(buffer[cursor])
            let entryLength = saLen == 0 ? MemoryLayout<sockaddr>.size : roundUp(saLen)

            if saLen >= MemoryLayout<sockaddr_in>.size {
                let address: sockaddr_in = buffer.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: cursor, as: sockaddr_in.self)
                }
                if address.sin_family == UInt8(AF_INET) {
                    var addr = address.sin_addr
                    var hostBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &addr, &hostBuffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                        let text = String(cString: hostBuffer)
                        if bit == 0 /* RTA_DST */ {
                            sawDefaultDestination = (text == "0.0.0.0")
                        } else if bit == 1 /* RTA_GATEWAY */, sawDefaultDestination {
                            return text
                        }
                    }
                }
            }
            cursor += max(entryLength, MemoryLayout<sockaddr>.size)
        }
        return nil
    }
}
