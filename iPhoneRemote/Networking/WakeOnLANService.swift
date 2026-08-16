import Foundation
import Darwin

enum WakeOnLANService {
    enum WakeError: LocalizedError {
        case invalidHardwareAddress
        case unableToSend

        var errorDescription: String? {
            switch self {
            case .invalidHardwareAddress:
                return "This Mac doesn't have a valid saved wake address yet. Connect once while it is awake."
            case .unableToSend:
                return "The wake signal couldn't be sent on this network."
            }
        }
    }

    static func wake(macAddress: String, broadcastAddress: String?) async throws {
        guard let packet = magicPacket(for: macAddress) else {
            throw WakeError.invalidHardwareAddress
        }

        try await Task.detached(priority: .userInitiated) {
            let targets = Array(Set([broadcastAddress, "255.255.255.255"].compactMap { $0 }))
            var sentAtLeastOnce = false
            for _ in 0..<3 {
                for target in targets {
                    for port in [UInt16(9), UInt16(7)] {
                        sentAtLeastOnce = send(packet, to: target, port: port) || sentAtLeastOnce
                    }
                }
                usleep(120_000)
            }
            guard sentAtLeastOnce else { throw WakeError.unableToSend }
        }.value
    }

    static func magicPacket(for macAddress: String) -> Data? {
        let normalized = macAddress.replacingOccurrences(of: "-", with: ":")
        let components = normalized.split(separator: ":")
        guard components.count == 6 else { return nil }
        let hardwareBytes = components.compactMap { UInt8($0, radix: 16) }
        guard hardwareBytes.count == 6 else { return nil }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: hardwareBytes) }
        return packet
    }

    private static func send(_ packet: Data, to host: String, port: UInt16) -> Bool {
        let socketDescriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else { return false }
        defer { Darwin.close(socketDescriptor) }

        var enableBroadcast: Int32 = 1
        guard setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &enableBroadcast,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else { return false }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(port.bigEndian)
        guard host.withCString({ inet_pton(AF_INET, $0, &destination.sin_addr) }) == 1 else { return false }

        let sentBytes = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                packet.withUnsafeBytes { bytes in
                    Darwin.sendto(
                        socketDescriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        return sentBytes == packet.count
    }
}
