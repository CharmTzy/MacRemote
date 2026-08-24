import Foundation
import OSLog

/// Tries, in order of preference, every way a home router might let inbound
/// internet traffic reach this Mac's control port:
///
/// 1. **PCP** MAP request to the gateway (RFC 6887)
/// 2. **NAT-PMP** map request (RFC 6886) — the older subset
/// 3. **UPnP IGD** `AddPortMapping` via SOAP — the most widely supported
///
/// A successful mapping is renewed by the owner (`ReachabilityController`)
/// roughly twice per lease lifetime; re-running the same request *is* the
/// renewal, per both RFCs. If all three fail, that's reported too: it means
/// either UPnP is disabled on the router or the ISP puts us behind
/// carrier-grade NAT (in which case IPv6 may still work — see the
/// snapshot's IPv6 list).
struct NATMappingResult: Equatable {
    let externalIP: String?
    let externalPort: UInt16
    let method: String
    /// Public IP looks private/CG-NAT (100.64/10 etc.) — mapping probably
    /// won't accept inbound connections from the real internet.
    let likelyBehindCarrierNAT: Bool

    static let none = NATMappingResult(externalIP: nil, externalPort: 0, method: "none", likelyBehindCarrierNAT: false)
}

enum NATPortMapper {
    /// Lifetime we ask for (2 h); renewed around half-life by the caller.
    static let requestedLifetimeSeconds: UInt32 = 7200

    static func establishMapping(internalPort: UInt16, lanIPv4: String?, suggestedExternalPort: UInt16 = ServiceConstants.defaultControlPort) async -> NATMappingResult {
        guard let gatewayIP = DefaultGateway.ipv4Gateway() else {
            Logging.anywhere.notice("No IPv4 default gateway found; skipping router port mapping")
            return .none
        }

        // PCP first — its MAP response already carries the assigned external
        // address, so no extra round trips are needed.
        if let pcp = pcpMap(gatewayIP: gatewayIP, internalPort: internalPort, lanIPv4: lanIPv4, suggestedExternalPort: suggestedExternalPort) {
            return await result(reportedIP: pcp.externalIPv4, port: pcp.externalPort, method: "PCP")
        }

        if let natpmp = natPMPMap(gatewayIP: gatewayIP, internalPort: internalPort, suggestedExternalPort: suggestedExternalPort) {
            return await result(reportedIP: natpmp.externalIP, port: natpmp.mappedPort, method: "NAT-PMP")
        }

        // UPnP last — discovery alone costs a few seconds of SSDP waiting.
        let gateways = await UPnPGatewayClient.discoverGateways()
        for gateway in gateways {
            guard let lanIPv4, !lanIPv4.isEmpty else { break }
            if let mapped = await UPnPGatewayClient.mapTCP(
                gateway: gateway,
                internalHost: lanIPv4,
                internalPort: internalPort,
                externalPort: suggestedExternalPort
            ) {
                Logging.anywhere.info("UPnP mapping established via \(gateway.serviceType, privacy: .public)")
                return await result(reportedIP: mapped.externalIP, port: mapped.mappedPort, method: "UPnP")
            }
        }

        Logging.anywhere.notice("No router protocol accepted a port mapping (PCP/NAT-PMP/UPnP)")
        return .none
    }

    // MARK: PCP

    private static func pcpMap(gatewayIP: String, internalPort: UInt16, lanIPv4: String?, suggestedExternalPort: UInt16) -> NATMappingMessages.PCPMapResponse? {
        var nonce = Data(count: 12)
        let status = nonce.withUnsafeMutableBytes { rawBuffer -> Int32 in
            SecRandomCopyBytes(kSecRandomDefault, 12, rawBuffer.baseAddress!)
        }
        guard status == errSecSuccess,
              let request = NATMappingMessages.pcpMapTCPRequest(
                clientIPv4: lanIPv4, nonce: nonce,
                internalPort: internalPort,
                suggestedExternalPort: suggestedExternalPort,
                lifetimeSeconds: requestedLifetimeSeconds
              ),
              let response = UDPSimpleExchange.send(
                host: gatewayIP, port: NATMappingMessages.pcpServerPort,
                request: request, timeoutSeconds: 1.5
              ) else {
            return nil
        }
        guard let parsed = NATMappingMessages.parsePCPMapResponse(response, nonce: nonce) else {
            Logging.anywhere.info("Gateway didn't answer PCP MAP (trying NAT-PMP next)")
            return nil
        }
        Logging.anywhere.info("PCP mapping established: external port \(parsed.externalPort)")
        return parsed
    }

    // MARK: NAT-PMP

    private struct NATPMPOutcome {
        let mappedPort: UInt16
        let externalIP: String?
    }

    private static func natPMPMap(gatewayIP: String, internalPort: UInt16, suggestedExternalPort: UInt16) -> NATPMPOutcome? {
        let addressResponse = UDPSimpleExchange.send(
            host: gatewayIP, port: NATMappingMessages.pcpServerPort,
            request: NATMappingMessages.natpmpPublicAddressRequest(), timeoutSeconds: 1.0
        )
        var externalIP: String?
        switch addressResponse.flatMap({ NATMappingMessages.parseNATPMPResponse($0, expectedOpcode: 0) }) {
        case .publicAddress(let ipv4):
            externalIP = ipv4
        default:
            return nil // didn't answer even the simplest request — skip
        }

        let mapResponse = UDPSimpleExchange.send(
            host: gatewayIP, port: NATMappingMessages.pcpServerPort,
            request: NATMappingMessages.natpmpMapTCPRequest(
                internalPort: internalPort,
                suggestedExternalPort: suggestedExternalPort,
                lifetimeSeconds: requestedLifetimeSeconds
            ),
            timeoutSeconds: 1.5
        )
        switch mapResponse.flatMap({ NATMappingMessages.parseNATPMPResponse($0, expectedOpcode: 2) }) {
        case .map(let mappedPort, _):
            Logging.anywhere.info("NAT-PMP mapping established: external port \(mappedPort)")
            return NATPMPOutcome(mappedPort: mappedPort, externalIP: externalIP)
        default:
            return nil
        }
    }

    // MARK: shared

    private static func result(reportedIP: String?, port: UInt16, method: String) async -> NATMappingResult {
        var ip = reportedIP
        if ip == nil {
            ip = await publicIPOrFallback()
        }
        return NATMappingResult(
            externalIP: ip,
            externalPort: port,
            method: method,
            likelyBehindCarrierNAT: ip.map(Self.looksPrivate) ?? false
        )
    }

    /// Best-effort public-IP lookup when the router protocol didn't report
    /// one. Only meaningful alongside a successful mapping.
    static func publicIPOrFallback() async -> String? {
        if let url = URL(string: "https://api.ipify.org"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let text = String(data: data, encoding: .utf8) {
            return ConnectCandidateBuilder.sanitizedIPv4(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func looksPrivate(_ ipv4: String) -> Bool {
        ConnectCandidateBuilder.isPrivateIPv4(ipv4)
    }
}
