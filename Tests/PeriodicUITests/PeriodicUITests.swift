import XCTest

@MainActor
final class PeriodicUITests: XCTestCase {
    func testMainWindowAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-appearance", "system"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["暂无内容"].waitForExistence(timeout: 10))
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        XCTAssertTrue(app.popUpButtons["appearance-picker"].waitForExistence(timeout: 5))
    }

    func testNewWindowUsesIndependentScene() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["暂无内容"].waitForExistence(timeout: 10))
        let destinations = app.descendants(matching: .any)
            .matching(identifier: "destination-workspace")
        XCTAssertEqual(destinations.count, 1)

        app.typeKey("s", modifierFlags: [.command, .control])
        let sidebarHidden = NSPredicate(format: "count == 0")
        expectation(for: sidebarHidden, evaluatedWith: destinations)
        waitForExpectations(timeout: 5)

        let initialCount = app.windows.count
        app.typeKey("n", modifierFlags: .command)
        let expectedCount = NSPredicate(format: "count == %d", initialCount + 1)
        expectation(for: expectedCount, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)

        let newWindowHasIndependentSidebar = NSPredicate(format: "count == 1")
        expectation(for: newWindowHasIndependentSidebar, evaluatedWith: destinations)
        waitForExpectations(timeout: 5)
    }
}
