import XCTest

final class RunningAppsDockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCanActivateTwoRunningApplicationsInSequence() throws {
        let app = XCUIApplication()
        app.launch()
        if app.alerts.buttons["Allow"].waitForExistence(timeout: 3) {
            app.alerts.buttons["Allow"].tap()
        }
        XCUIDevice.shared.orientation = .landscapeLeft

        let macRow = app.buttons.containing(.staticText, identifier: "Wai’s MacBook Air").firstMatch
        XCTAssertTrue(macRow.waitForExistence(timeout: 10), "The Mac did not appear in My Macs")
        macRow.tap()

        let connect = app.buttons["Connect to Mac"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        keepScreenshot(named: "mac-detail-landscape")
        connect.tap()

        let pairingSheet = app.navigationBars["Pair iPhone"]
        if pairingSheet.waitForExistence(timeout: 3),
           let pairingCode = ProcessInfo.processInfo.environment["MACREMOTE_PAIRING_CODE"] {
            let pairingField = app.textFields["847291"]
            XCTAssertTrue(pairingField.waitForExistence(timeout: 5))
            pairingField.tap()
            pairingField.typeText(pairingCode)
            app.buttons["Pair"].tap()
        }

        let viewScreen = app.buttons["Start Remote Control"]
        if !viewScreen.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(viewScreen.waitForExistence(timeout: 15), "The control connection did not become ready")
        viewScreen.tap()

        let appButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open '"))
        XCTAssertTrue(appButtons.firstMatch.waitForExistence(timeout: 20), "The running-app dock did not appear")
        XCTAssertGreaterThanOrEqual(appButtons.count, 2, "Two running Mac applications are needed for this test")
        XCTAssertTrue(
            app.descendants(matching: .any)["Mac trackpad"].waitForExistence(timeout: 5),
            "The embedded lower-right trackpad did not appear"
        )
        keepScreenshot(named: "remote-control-landscape")

        let firstLabel = appButtons.element(boundBy: 0).label
        appButtons.element(boundBy: 0).tap()
        sleep(2)

        let refreshedButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open '"))
        XCTAssertTrue(refreshedButtons.firstMatch.waitForExistence(timeout: 5))
        let second = refreshedButtons.allElementsBoundByIndex.first { $0.label != firstLabel }
        XCTAssertNotNil(second, "A second application button was not available after the first activation")
        XCTAssertTrue(second?.isHittable == true, "The dock stopped accepting taps after its first update")
        second?.tap()
        sleep(2)

        XCTAssertTrue(refreshedButtons.firstMatch.exists, "The dock disappeared after the second activation")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
