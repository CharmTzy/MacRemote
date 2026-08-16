import XCTest

final class RunningAppsDockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCanActivateTwoRunningApplicationsInSequence() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        let macRow = app.buttons.containing(.staticText, identifier: "Wai’s MacBook Air").firstMatch
        XCTAssertTrue(macRow.waitForExistence(timeout: 10), "The Mac did not appear in My Macs")
        macRow.tap()

        let connect = app.buttons["Connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.tap()

        let viewScreen = app.buttons["View Screen"]
        XCTAssertTrue(viewScreen.waitForExistence(timeout: 15), "The control connection did not become ready")
        viewScreen.tap()

        let appButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open '"))
        XCTAssertTrue(appButtons.firstMatch.waitForExistence(timeout: 20), "The running-app dock did not appear")
        XCTAssertGreaterThanOrEqual(appButtons.count, 2, "Two running Mac applications are needed for this test")
        XCTAssertTrue(
            app.descendants(matching: .any)["Mac trackpad"].waitForExistence(timeout: 5),
            "The embedded lower-right trackpad did not appear"
        )

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
}
