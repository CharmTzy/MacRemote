import Foundation
import OSLog

/// Discovers UPnP InternetGatewayDevices on the LAN (SSDP M-SEARCH), reads
/// each device's description document, and performs the two SOAP actions we
/// need: `AddPortMapping` and `GetExternalIPAddress`. Transport only —
/// parsing lives in `UPnPDescriptionParser`/`UPnPSOAP`.
enum UPnPGatewayClient {
    struct Gateway {
        let controlURL: URL
        let serviceType: String
    }

    struct MapResult {
        let externalIP: String?
        let mappedPort: UInt16
        /// True when the router accepted the mapping but only as a
        /// permanent lease (error 725 retried with duration 0).
        let permanentLease: Bool
    }

    private static let searchTargets = [
        "urn:schemas-upnp-org:device:InternetGatewayDevice:2",
        "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
        "urn:schemas-upnp-org:service:WANIPConnection:2",
        "urn:schemas-upnp-org:service:WANIPConnection:1",
        "urn:schemas-upnp-org:service:WANPPPConnection:1"
    ]

    static func discoverGateways(windowSeconds: Double = 3.0) async -> [Gateway] {
        // One search per ST: a single M-SEARCH may list only one target, and
        // strict devices ignore anything else. Stop after the first family
        // that answers — a gateway advertising WANIPConnection is what we want.
        var locations = Set<String>()
        for target in searchTargets {
            let msearch = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(target)\r\n\r\n"
            let responses = UDPSimpleExchange.multicastCollect(
                host: "239.255.255.250", port: 1900,
                request: Data(msearch.utf8),
                windowSeconds: windowSeconds
            )
            for response in responses {
                if let location = headerValue("LOCATION", in: response) {
                    locations.insert(location)
                }
            }
            if !locations.isEmpty { break }
        }

        var gateways: [Gateway] = []
        for location in locations {
            guard let url = URL(string: location),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let parsed = UPnPDescriptionParser.parse(data: data),
                  let service = UPnPDescriptionParser.preferredService(from: parsed.services),
                  let controlURLString = UPnPDescriptionParser.resolveControlURL(
                    service.controlURL, urlBase: parsed.urlBase, documentURL: location),
                  let controlURL = URL(string: controlURLString) else {
                continue
            }
            gateways.append(Gateway(controlURL: controlURL, serviceType: service.serviceType))
        }
        return gateways
    }

    /// Asks `gateway` to forward `externalPort` to this Mac's `internalPort`
    /// over TCP, then asks it what its public IPv4 is.
    static func mapTCP(
        gateway: Gateway,
        internalHost: String,
        internalPort: UInt16,
        externalPort: UInt16
    ) async -> MapResult? {
        // Bounded lease renewed by ReachabilityController; some IGD1 boxes
        // only accept a permanent lease — retry with 0 on error 725.
        var permanentLease = false
        var succeeded = await addPortMapping(
            gateway: gateway, internalHost: internalHost, internalPort: internalPort,
            externalPort: externalPort, leaseDuration: 3600
        )
        if !succeeded {
            if await addPortMapping(gateway: gateway, internalHost: internalHost, internalPort: internalPort,
                                    externalPort: externalPort, leaseDuration: 0) {
                succeeded = true
                permanentLease = true
            }
        }
        guard succeeded else { return nil }

        let externalIP = await fetchExternalIP(gateway: gateway)
        return MapResult(externalIP: externalIP, mappedPort: externalPort, permanentLease: permanentLease)
    }

    /// Best-effort cleanup on quit. PCP/NAT-PMP mappings expire on their
    /// own; a permanent UPnP lease would linger in the router's table.
    static func removeMapping(gateway: Gateway, externalPort: UInt16) async {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:DeletePortMapping xmlns:u="\(gateway.serviceType)">
              <NewRemoteHost></NewRemoteHost>
              <NewExternalPort>\(externalPort)</NewExternalPort>
              <NewProtocol>TCP</NewProtocol>
            </u:DeletePortMapping>
          </s:Body>
        </s:Envelope>
        """
        _ = try? await soapCall(url: gateway.controlURL, serviceType: gateway.serviceType,
                                action: "DeletePortMapping", body: body)
    }

    private static func addPortMapping(
        gateway: Gateway, internalHost: String, internalPort: UInt16,
        externalPort: UInt16, leaseDuration: Int
    ) async -> Bool {
        let body = UPnPSOAP.addPortMappingBody(
            serviceType: gateway.serviceType,
            externalPort: externalPort,
            internalHost: internalHost,
            internalPort: internalPort,
            description: "Mac Remote",
            leaseDuration: leaseDuration
        )
        guard let (_, response) = try? await soapCall(
            url: gateway.controlURL, serviceType: gateway.serviceType,
            action: "AddPortMapping", body: body
        ), let text = String(data: response, encoding: .utf8) else {
            return false
        }
        if UPnPSOAP.isFault(text) {
            Logging.anywhere.warning("AddPortMapping fault \(UPnPSOAP.errorCode(text).map(String.init) ?? "?", privacy: .public)")
            return false
        }
        return true
    }

    static func fetchExternalIP(gateway: Gateway) async -> String? {
        let body = UPnPSOAP.getExternalIPAddressBody(serviceType: gateway.serviceType)
        guard let (_, response) = try? await soapCall(
            url: gateway.controlURL, serviceType: gateway.serviceType,
            action: "GetExternalIPAddress", body: body
        ), let text = String(data: response, encoding: .utf8) else {
            return nil
        }
        return UPnPSOAP.externalIPAddress(fromResponseBody: text)
    }

    private static func soapCall(url: URL, serviceType: String, action: String, body: String) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (http, data)
    }

    private static func headerValue(_ name: String, in datagram: Data) -> String? {
        guard let text = String(data: datagram, encoding: .isoLatin1) else { return nil }
        for line in text.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).uppercased() == name.uppercased() {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
