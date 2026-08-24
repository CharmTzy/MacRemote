import Foundation

/// Sent by the Mac on the control connection right after authentication,
/// and again whenever its network situation changes. The iPhone persists
/// these endpoints in the paired-device record so a future connection can
/// dial them even when Bonjour is unavailable — this is the no-iCloud
/// fallback path for "connect from anywhere" (the primary path is the
/// iCloud record; see ARCHITECTURE.md).
struct ReachabilityUpdatePayload: Sendable, Equatable {
    var lanIPv4Address: String?
    var wanIPv4Address: String?
    var externalPort: UInt16?
    var ipv6Addresses: [String]
    var vpnIPv4Addresses: [String]
    var wakeMACAddress: String?

    init(
        lanIPv4Address: String? = nil,
        wanIPv4Address: String? = nil,
        externalPort: UInt16? = nil,
        ipv6Addresses: [String] = [],
        vpnIPv4Addresses: [String] = [],
        wakeMACAddress: String? = nil
    ) {
        self.lanIPv4Address = lanIPv4Address
        self.wanIPv4Address = wanIPv4Address
        self.externalPort = externalPort
        self.ipv6Addresses = ipv6Addresses
        self.vpnIPv4Addresses = vpnIPv4Addresses
        self.wakeMACAddress = wakeMACAddress
    }

    func encode(into writer: inout ByteWriter) {
        writer.writeString(lanIPv4Address ?? "")
        writer.writeString(wanIPv4Address ?? "")
        writer.writeBool(externalPort != nil)
        writer.writeUInt16(externalPort ?? 0)
        let addresses = ipv6Addresses.prefix(8)
        writer.writeUInt8(UInt8(addresses.count))
        for address in addresses {
            writer.writeString(address)
        }
        let vpnAddresses = vpnIPv4Addresses.prefix(8)
        writer.writeUInt8(UInt8(vpnAddresses.count))
        for address in vpnAddresses {
            writer.writeString(address)
        }
        writer.writeString(wakeMACAddress ?? "")
    }

    static func decode(from reader: inout ByteReader) throws -> ReachabilityUpdatePayload {
        let lan = try reader.readString()
        let wan = try reader.readString()
        let hasExternalPort = try reader.readBool()
        let externalPort = try reader.readUInt16()
        let count = try reader.readUInt8()
        var addresses: [String] = []
        addresses.reserveCapacity(Int(count))
        for _ in 0..<count {
            addresses.append(try reader.readString())
        }

        // VPN list added later — tolerate its absence so a newer Mac can
        // still talk to an older iPhone build without corrupting the frame.
        var vpnAddresses: [String] = []
        if reader.remainingBytes > 2 {
            let vpnCount = try reader.readUInt8()
            vpnAddresses.reserveCapacity(Int(vpnCount))
            for _ in 0..<vpnCount {
                vpnAddresses.append(try reader.readString())
            }
        }

        let wakeMAC = reader.remainingBytes >= 2 ? try reader.readString() : ""
        return ReachabilityUpdatePayload(
            lanIPv4Address: lan.isEmpty ? nil : lan,
            wanIPv4Address: wan.isEmpty ? nil : wan,
            externalPort: hasExternalPort ? externalPort : nil,
            ipv6Addresses: addresses,
            vpnIPv4Addresses: vpnAddresses,
            wakeMACAddress: wakeMAC.isEmpty ? nil : wakeMAC
        )
    }
}
