import Foundation

/// Extracts what we need from a UPnP IGD device-description XML document:
/// the SOAP `controlURL` for its WANIPConnection/WANPPPConnection service.
/// Pure Foundation XMLParser, no third-party dependencies; the transport
/// (SSDP discovery, HTTP fetch, SOAP call) lives in `UPnPGatewayClient`.
final class UPnPDescriptionParser: NSObject, XMLParserDelegate {
    struct GatewayService: Equatable {
        let serviceType: String
        let controlURL: String
    }

    private var currentText = ""
    private var currentServiceType: String?
    private var currentControlURL: String?
    private var services: [GatewayService] = []
    /// `<URLBase>` if present — control URLs are relative to it, falling
    /// back to the document's own retrieval URL when absent (per UPnP 1.0).
    private(set) var urlBase: String?

    static func parse(data: Data) -> (services: [GatewayService], urlBase: String?)? {
        let parser = UPnPDescriptionParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return (parser.services, parser.urlBase)
    }

    /// Picks the best service for port mapping: WANIPConnection beats
    /// WANPPPConnection (PPP is for PPPoE gateways but usually proxies the
    /// same actions), newest version first.
    static func preferredService(from services: [GatewayService]) -> GatewayService? {
        services
            .filter { $0.serviceType.contains("WANIPConnection") || $0.serviceType.contains("WANPPPConnection") }
            .max { lhs, rhs in
                rank(lhs) < rank(rhs)
            }
    }

    private static func rank(_ service: GatewayService) -> Int {
        let version = service.serviceType.split(separator: ":").last.flatMap { Int($0) } ?? 1
        return (service.serviceType.contains("WANIPConnection") ? 100 : 0) + version
    }

    /// Resolves a possibly-relative `controlURL` against the description's
    /// base URL. Returns nil when the pieces can't be combined into a valid
    /// absolute http(s) URL.
    static func resolveControlURL(_ controlURL: String, urlBase: String?, documentURL: String?) -> String? {
        let trimmed = controlURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: trimmed), absolute.scheme == "http" || absolute.scheme == "https" {
            return trimmed
        }
        for base in [urlBase, documentURL].compactMap({ $0 }).map(URL.init(string:)) {
            guard let base else { continue }
            if let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL.absoluteString,
               resolved.hasPrefix("http://") || resolved.hasPrefix("https://") {
                return resolved
            }
        }
        return nil
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        if (elementName.localizedName ?? elementName) == "service" {
            currentServiceType = nil
            currentControlURL = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.localizedName ?? elementName
        switch name {
        case "URLBase":
            urlBase = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "serviceType":
            currentServiceType = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "controlURL":
            currentControlURL = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "service":
            if let serviceType = currentServiceType, let controlURL = currentControlURL {
                services.append(GatewayService(serviceType: serviceType, controlURL: controlURL))
            }
            currentServiceType = nil
            currentControlURL = nil
        default:
            break
        }
    }
}

private extension String {
    /// XMLParser reports names with any namespace prefix attached; strip it.
    var localizedName: String? {
        split(separator: ":").last.map(String.init)
    }
}

/// Builds and reads the tiny slice of SOAP/UPnP we need, as pure string
/// operations so they're unit-testable without a gateway.
enum UPnPSOAP {
    /// SOAPAction for `AddPortMapping` (IGD:1 and :2 share the action name).
    static func addPortMappingAction(serviceType: String) -> String { "\(serviceType)#AddPortMapping" }

    static func addPortMappingBody(
        serviceType: String,
        externalPort: UInt16,
        internalHost: String,
        internalPort: UInt16,
        description: String,
        leaseDuration: Int
    ) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:AddPortMapping xmlns:u="\(serviceType)">
              <NewRemoteHost></NewRemoteHost>
              <NewExternalPort>\(externalPort)</NewExternalPort>
              <NewProtocol>TCP</NewProtocol>
              <NewInternalPort>\(internalPort)</NewInternalPort>
              <NewInternalClient>\(internalHost)</NewInternalClient>
              <NewEnabled>1</NewEnabled>
              <NewPortMappingDescription>\(description)</NewPortMappingDescription>
              <NewLeaseDuration>\(leaseDuration)</NewLeaseDuration>
            </u:AddPortMapping>
          </s:Body>
        </s:Envelope>
        """
    }

    static func getExternalIPAddressBody(serviceType: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetExternalIPAddress xmlns:u="\(serviceType)" />
          </s:Body>
        </s:Envelope>
        """
    }

    /// Extracts `<NewExternalIPAddress>` from a GetExternalIPAddress
    /// response body.
    static func externalIPAddress(fromResponseBody body: String) -> String? {
        value(of: "NewExternalIPAddress", in: body).flatMap(UPnPDescriptionParsing.sanitizedIPv4)
    }

    /// True when the response is a SOAP fault. IGD port-mapping errors put
    /// an `UPnPError` block inside `<detail>`.
    static func isFault(_ body: String) -> Bool {
        body.contains("<s:Fault") || body.contains(":Fault")
    }

    /// UPnP error code from a fault body (`<errorCode>`), when present.
    /// Notably 725 = OnlyPermanentLeaseSupported — worth retrying with an
    /// infinite lease.
    static func errorCode(_ body: String) -> Int? {
        value(of: "errorCode", in: body).flatMap(Int.init)
    }

    private static func value(of element: String, in body: String) -> String? {
        guard let start = body.range(of: "<\(element)>"),
              let end = body.range(of: "</\(element)>", range: start.upperBound..<body.endIndex) else {
            return nil
        }
        return String(body[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum UPnPDescriptionParsing {
    /// Guards a parsed external-IP value against garbage before we trust it.
    static func sanitizedIPv4(_ value: String?) -> String? {
        ConnectCandidateBuilder.sanitizedIPv4(value)
    }
}
