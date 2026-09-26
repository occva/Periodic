import XCTest

@MainActor
final class PeriodicUITests: XCTestCase {
    func testMainWindowAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-appearance", "system", "-store-in-memory"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["dashboard-page"].waitForExistence(timeout: 10))
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        XCTAssertTrue(app.popUpButtons["appearance-picker"].waitForExistence(timeout: 5))
    }

    func testTemplateLibraryKeepsItsSidebarVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-store-in-memory"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["dashboard-page"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["destination-templates"].click()

        let templateSidebar = app.descendants(matching: .any)["template-library-sidebar"]
        XCTAssertTrue(templateSidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["template-library-content"]
                .waitForExistence(timeout: 5)
        )
    }

    func testNewWindowUsesIndependentScene() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-store-in-memory"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["dashboard-page"].waitForExistence(timeout: 10))
        let destinations = app.descendants(matching: .any)
            .matching(identifier: "destination-overview")
        XCTAssertEqual(destinations.count, 1)

        app.typeKey("s", modifierFlags: [.command, .control])
        let sidebarHidden = NSPredicate(format: "count == 0")
        expectation(for: sidebarHidden, evaluatedWith: destinations)
        waitForExpectations(timeout: 5)

        let initialCount = app.windows.count
        app.typeKey("n", modifierFlags: [.command, .shift])
        let expectedCount = NSPredicate(format: "count == %d", initialCount + 1)
        expectation(for: expectedCount, evaluatedWith: app.windows)
        waitForExpectations(timeout: 5)

        let newWindowHasIndependentSidebar = NSPredicate(format: "count == 1")
        expectation(for: newWindowHasIndependentSidebar, evaluatedWith: destinations)
        waitForExpectations(timeout: 5)
    }

    func testCreateSubscriptionFromKeyboard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-store-in-memory"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["dashboard-page"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["destination-overview"].click()
        XCTAssertTrue(app.descendants(matching: .any)["overview-page"].waitForExistence(timeout: 5))
        app.typeKey("n", modifierFlags: .command)

        let nameField = app.textFields["subscription-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText("Test123")

        let amountField = app.textFields["subscription-amount"]
        amountField.click()
        amountField.typeText("12.50")

        let currencyPicker = app.popUpButtons["subscription-currency"]
        XCTAssertTrue(currencyPicker.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(amountField.frame.maxX, currencyPicker.frame.minX)

        app.buttons["save-subscription"].click()
        XCTAssertFalse(app.buttons["save-subscription"].waitForExistence(timeout: 2))
        let resultCount = app.staticTexts
            .matching(NSPredicate(format: "value CONTAINS %@", "全库 1"))
            .firstMatch
        XCTAssertTrue(resultCount.waitForExistence(timeout: 5))
        XCTAssertTrue((resultCount.value as? String)?.contains("当前结果 1") == true)
        let savedAmount = app.staticTexts
            .matching(NSPredicate(format: "value == %@", "CNY 12.50"))
            .firstMatch
        XCTAssertTrue(savedAmount.waitForExistence(timeout: 5))
    }

    func testAppleIconPickerCanBeDismissedWithEscape() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-store-in-memory"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["dashboard-page"].waitForExistence(timeout: 10))
        app.typeKey("n", modifierFlags: .command)

        let appleSearchButton = app.buttons["search-apple-icon"]
        XCTAssertTrue(appleSearchButton.waitForExistence(timeout: 5))
        appleSearchButton.click()

        let queryField = app.textFields["apple-icon-query"]
        XCTAssertTrue(queryField.waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertFalse(queryField.waitForExistence(timeout: 2))
    }

    func testCreatingSubscriptionRefreshesEveryOpenWindow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-store-in-memory"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.descendants(matching: .any)["dashboard-page"].waitForExistence(timeout: 10))
        app.typeKey("n", modifierFlags: [.command, .shift])

        let dashboards = app.descendants(matching: .any).matching(identifier: "dashboard-page")
        expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: dashboards)
        waitForExpectations(timeout: 5)

        app.typeKey("n", modifierFlags: .command)
        let nameField = app.textFields["subscription-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText("Shared Window Item")
        let amountField = app.textFields["subscription-amount"]
        amountField.click()
        amountField.typeText("9.99")
        let expiryToggle = app.descendants(matching: .any)["subscription-expiry-enabled"]
        XCTAssertTrue(expiryToggle.waitForExistence(timeout: 3))
        expiryToggle.click()

        let saveButton = app.buttons["save-subscription"]
        saveButton.click()
        XCTAssertFalse(saveButton.waitForExistence(timeout: 3))

        for index in 0..<dashboards.count {
            let activeCount = dashboards.element(boundBy: index)
                .staticTexts["dashboard-active-count"]
            XCTAssertTrue(activeCount.waitForExistence(timeout: 8))
            XCTAssertEqual(activeCount.value as? String, "1")
        }
    }

}
