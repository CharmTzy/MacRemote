import Foundation
import Darwin

/// Minimal blocking UDP request/response over a POSIX socket — the same
/// style as `WakeOnLANService`, but with a receive step and a deadline.
/// Used for NAT-PMP/PCP (gateway:5351) and SSDP M-SEARCH; both are tiny,
/// local-network, fire-once protocols where a full Network.framework
/// session would be ceremony.
enum UDPSimpleExchange {
    /// Sends `request` to `host:port` and returns the first response
    /// datagram received within the timeout, or nil.
    static func send(host: String, port: UInt16, request: Data, timeoutSeconds: Double) -> Data? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_family = UInt8(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }

        // Receive deadline so a silent gateway can't stall us.
        var tv = timeval(tv_sec: Int(timeoutSeconds), tv_usec: 0)
        _ = withUnsafePointer(to: &tv) {
            $0.withMemoryRebound(to: timeval.self, capacity: 1) {
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
            }
        }

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        let sent = request.withUnsafeBytes { rawBuffer -> ssize_t in
            Darwin.send(fd, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        guard sent == request.count else { return nil }

        var response = Data(count: 2048)
        let received = response.withUnsafeMutableBytes { rawBuffer -> Int in
            recv(fd, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        guard received > 0 else { return nil }
        return response.prefix(received)
    }

    /// Sends `request` to the SSDP multicast group and collects every
    /// unicast response datagram that arrives within the timeout window
    /// (devices answer at staggered delays per MX).
    static func multicastCollect(host: String, port: UInt16, request: Data, windowSeconds: Double) -> [Data] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_family = UInt8(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return [] }

        let sent = request.withUnsafeBytes { rawBuffer -> ssize_t in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, rawBuffer.baseAddress, rawBuffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == request.count else { return [] }

        let deadline = Date().addingTimeInterval(windowSeconds)
        var responses: [Data] = []
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            var tv = timeval(tv_sec: Int(remaining), tv_usec: 0)
            _ = withUnsafeMutablePointer(to: &tv) {
                $0.withMemoryRebound(to: timeval.self, capacity: 1) {
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
                }
            }
            var buffer = [UInt8](repeating: 0, count: 2048)
            let received = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                recv(fd, rawBuffer.baseAddress, rawBuffer.count, 0)
            }
            guard received > 0 else { break } // timeout expired
            responses.append(Data(buffer.prefix(received)))
        }
        return responses
    }
}
