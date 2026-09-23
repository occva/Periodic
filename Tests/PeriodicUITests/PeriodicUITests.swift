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
        XCTAssertTrue(app.searchFields["搜索模板名称或别名"].waitForExistence(timeout: 5))
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
        app.buttons["save-subscription"].click()

        XCTAssertTrue(app.windows.element(boundBy: 0).staticTexts["1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.windows.element(boundBy: 1).staticTexts["1"].waitForExistence(timeout: 8))
    }

}
