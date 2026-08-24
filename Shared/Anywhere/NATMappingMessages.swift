import Foundation

/// Wire-format helpers for the two router port-mapping protocols we speak,
/// kept pure so they can be unit tested without a router: the transport
/// lives in `NATPortMapper` (Mac side).
///
/// Both protocols run over UDP to the gateway on port 5351:
///
/// - NAT-PMP (RFC 6886): 2-byte requests, simple fixed-layout responses.
/// - PCP (RFC 6887): its successor — 24-byte base header + opcode payload,
///   result code is the single byte at offset 3. Many routers speak only
///   one of the two protocols, so we try PCP first and fall back.
enum NATMappingMessages {
    static let pcpServerPort: UInt16 = 5351

    // MARK: NAT-PMP

    /// NAT-PMP Map TCP request: version 0, opcode 2.
    /// `[ver][opcode][reserved][internal port][suggested ext port][lifetime]`
    static func natpmpMapTCPRequest(internalPort: UInt16, suggestedExternalPort: UInt16, lifetimeSeconds: UInt32) -> Data {
        var writer = ByteWriter()
        writer.writeUInt8(0) // version
        writer.writeUInt8(2) // opcode: MAP TCP
        writer.writeUInt8(0) // reserved
        writer.writeUInt16(internalPort)
        writer.writeUInt16(suggestedExternalPort)
        writer.writeUInt32(lifetimeSeconds)
        return writer.data
    }

    /// NAT-PMP public-address request: version 0, opcode 0.
    static func natpmpPublicAddressRequest() -> Data {
        var writer = ByteWriter()
        writer.writeUInt8(0)
        writer.writeUInt8(0)
        return writer.data
    }

    enum NATPMPResponse: Equatable {
        case publicAddress(ipv4: String)
        case map(externalPort: UInt16, lifetimeSeconds: UInt32)
    }

    /// Parses a NAT-PMP response for `expectedOpcode` (0 = public address,
    /// 2 = map). Returns nil for malformed frames or any non-zero result
    /// code, which means "router refused / unsupported".
    static func parseNATPMPResponse(_ data: Data, expectedOpcode: UInt8) -> NATPMPResponse? {
        var reader = ByteReader(data)
        guard let version = try? reader.readUInt8(), version == 0,
              let opcode = try? reader.readUInt8(), opcode == expectedOpcode | 0x80,
              let result = try? reader.readUInt16(), result == 0,
              let _ = try? reader.readUInt32() else { return nil } // seconds since epoch

        switch expectedOpcode {
        case 0:
            guard let raw = try? reader.readUInt32() else { return nil }
            let address = [
                UInt8(truncatingIfNeeded: raw >> 24), UInt8(truncatingIfNeeded: raw >> 16),
                UInt8(truncatingIfNeeded: raw >> 8), UInt8(truncatingIfNeeded: raw)
            ].map { String($0) }.joined(separator: ".")
            return .publicAddress(ipv4: address)
        case 2:
            guard let _ = try? reader.discard(2), // private port echo
                  let externalPort = try? reader.readUInt16(),
                  let lifetime = try? reader.readUInt32(), lifetime > 0 else { return nil }
            return .map(externalPort: externalPort, lifetimeSeconds: lifetime)
        default:
            return nil
        }
    }

    // MARK: PCP (RFC 6887)

    struct PCPMapResponse: Equatable {
        let nonce: Data
        let lifetimeSeconds: UInt32
        let externalPort: UInt16
        /// Dotted-quad external IPv4 from the assigned-external-address
        /// field, or nil if the server reported an unspecified address.
        var externalIPv4: String?
    }

    /// PCP MAP request for TCP (Section 11.1). The 24-byte base header is
    /// followed by the MAP payload; the client's source address goes in the
    /// header as an IPv4-mapped IPv6 address.
    static func pcpMapTCPRequest(
        clientIPv4: String?,
        nonce: Data,
        internalPort: UInt16,
        suggestedExternalPort: UInt16,
        lifetimeSeconds: UInt32
    ) -> Data? {
        guard nonce.count == 12 else { return nil }
        var writer = ByteWriter()
        writer.writeUInt8(2) // version
        writer.writeUInt8(1) // opcode: MAP (request, R=0)
        writer.writeUInt8(0) // reserved
        writer.writeUInt8(0) // reserved
        writer.writeUInt32(lifetimeSeconds)
        writer.writeRawData(ipv4MappedAddress(clientIPv4)) // PCP client's IP
        writer.writeRawData(nonce)
        writer.writeUInt8(6) // protocol: TCP
        writer.writeUInt8(0) // reserved ×3
        writer.writeUInt8(0)
        writer.writeUInt8(0)
        writer.writeUInt16(internalPort)
        writer.writeUInt16(suggestedExternalPort)
        writer.writeRawData(Data(repeating: 0, count: 16)) // suggested external IP (:: = any)
        return writer.data
    }

    /// Response layout (Sections 7.2 + 11.1): ver(1) op(1) rsvd(1)
    /// result(1) lifetime(4) epoch(4) rsvd96(12) | nonce(12) proto(1)
    /// rsvd(3) internalPort(2) assignedExternalPort(2) externalIP(16).
    /// Minimum 60 bytes.
    static func parsePCPMapResponse(_ data: Data, nonce: Data) -> PCPMapResponse? {
        var reader = ByteReader(data)
        guard let version = try? reader.readUInt8(), version == 2,
              let opcode = try? reader.readUInt8(), opcode == 0x81,
              let _ = try? reader.discard(1),
              let result = try? reader.readUInt8(), result == 0,
              let lifetime = try? reader.readUInt32(),
              let _ = try? reader.discard(4 + 12), // epoch time + reserved 96 bits
              let responseNonce = try? reader.readRawBytes(12), responseNonce == nonce,
              let protocolByte = try? reader.readUInt8(), protocolByte == 6,
              let _ = try? reader.discard(3),
              let _ = try? reader.readUInt16(), // internal port echo
              let externalPort = try? reader.readUInt16() else { return nil }
        guard lifetime > 0 else { return nil }
        // Assigned external address (128-bit fixed field). IPv4 arrives as
        // an IPv4-mapped address; all zeros means "unspecified".
        var externalIPv4: String?
        if let rawAddress = try? reader.readRawBytes(16), rawAddress.count == 16,
           rawAddress[0] == 0, rawAddress[1] == 0, rawAddress[10] == 0xFF, rawAddress[11] == 0xFF {
            let octets = [rawAddress[12], rawAddress[13], rawAddress[14], rawAddress[15]]
            if octets.contains(where: { $0 != 0 }) {
                externalIPv4 = octets.map { String($0) }.joined(separator: ".")
            }
        }
        return PCPMapResponse(nonce: responseNonce, lifetimeSeconds: lifetime, externalPort: externalPort, externalIPv4: externalIPv4)
    }

    /// Encodes a dotted-quad IPv4 string as an IPv4-mapped IPv6 address
    /// (`::ffff:a.b.c.d`, 16 bytes). Falls back to all zeros.
    private static func ipv4MappedAddress(_ ipv4: String?) -> Data {
        var data = Data(repeating: 0, count: 16)
        data[10] = 0xFF
        data[11] = 0xFF
        if let ipv4 {
            let octets = ipv4.split(separator: ".").compactMap { UInt8($0) }
            if octets.count == 4 {
                for (index, octet) in octets.enumerated() {
                    data[12 + index] = octet
                }
            }
        }
        return data
    }
}
