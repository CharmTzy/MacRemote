import XCTest

final class UPnPParsingTests: XCTestCase {
    private let descriptionXML = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <specVersion><major>1</major><minor>0</minor></specVersion>
      <URLBase>http://192.168.0.1:5000</URLBase>
      <device>
        <deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:Layer3Forwarding:1</serviceType>
            <controlURL>/ctl/L3F</controlURL>
          </service>
          <service>
            <serviceType>urn:schemas-upnp-org:service:WANIPConnection:2</serviceType>
            <controlURL>/soap/server_sa/UPnP/UPS/WANIPConnection</controlURL>
          </service>
          <service>
            <serviceType>urn:schemas-upnp-org:service:WANPPPConnection:1</serviceType>
            <controlURL>/ctl/WANPPPConn</controlURL>
          </service>
        </serviceList>
      </device>
    </root>
    """

    func testParsesServicesAndPrefersWANIPConnection() throws {
        let parsed = try XCTUnwrap(UPnPDescriptionParser.parse(data: Data(descriptionXML.utf8)))

        XCTAssertEqual(parsed.urlBase, "http://192.168.0.1:5000")
        XCTAssertEqual(parsed.services.count, 3)

        let preferred = try XCTUnwrap(UPnPDescriptionParser.preferredService(from: parsed.services))
        XCTAssertTrue(preferred.serviceType.contains("WANIPConnection"))
        XCTAssertEqual(preferred.serviceType, "urn:schemas-upnp-org:service:WANIPConnection:2")
    }

    func testResolvesRelativeControlURLAgainstURLBase() {
        let resolved = UPnPDescriptionParser.resolveControlURL(
            "/soap/server_sa/UPnP/UPS/WANIPConnection",
            urlBase: "http://192.168.0.1:5000",
            documentURL: "http://192.168.0.1:5000/desc/igd.xml"
        )
        XCTAssertEqual(resolved, "http://192.168.0.1:5000/soap/server_sa/UPnP/UPS/WANIPConnection")
    }

    func testAbsoluteControlURLPassesThroughAndGarbageRejected() {
        XCTAssertEqual(
            UPnPDescriptionParser.resolveControlURL("http://192.168.0.1/control", urlBase: nil, documentURL: nil),
            "http://192.168.0.1/control"
        )
        XCTAssertNil(UPnPDescriptionParser.resolveControlURL("/only/a/path", urlBase: nil, documentURL: nil))
    }

    func testExternalIPAddressExtraction() {
        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetExternalIPAddressResponse xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
              <NewExternalIPAddress>203.0.113.99</NewExternalIPAddress>
            </u:GetExternalIPAddressResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertEqual(UPnPSOAP.externalIPAddress(fromResponseBody: body), "203.0.113.99")
        XCTAssertFalse(UPnPSOAP.isFault(body))
    }

    func testFaultDetectionAndErrorCode() {
        let fault = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body><s:Fault>
            <detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
              <errorCode>725</errorCode>
              <errorDescription>OnlyPermanentLeaseSupported</errorDescription>
            </UPnPError></detail>
          </s:Fault></s:Body>
        </s:Envelope>
        """
        XCTAssertTrue(UPnPSOAP.isFault(fault))
        XCTAssertEqual(UPnPSOAP.errorCode(fault), 725)
    }
}
