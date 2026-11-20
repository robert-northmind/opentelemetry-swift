/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import XCTest

/// Drives the watch app and checks the screen name after each step. The app prints every screen
/// change to the console with an `[otel]` prefix.
final class ScreenTrackingFlowTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
  }

  func testNavigationSheetTabsAndManualCalls() {
    expectScreen("Workouts")

    app.buttons["Workout 1"].tap()
    expectScreen("workout")
    app.buttons["Summary"].tap()
    expectScreen("summary")
    app.buttons["Pop to root"].tap()
    expectScreen("Workouts")

    app.buttons["Settings"].tap()
    expectScreen("Settings")
    app.buttons["Done"].tap()
    expectScreen("Workouts")

    app.buttons["Manual tab"].tap()
    expectScreen("Tab.manual")
    app.buttons["Set manual screen"].tap()
    expectScreen("Manual")
    app.buttons["Clear manual screen"].tap()
    expectScreen("Tab.manual")

    app.buttons["Workouts tab"].tap()
    expectScreen("Workouts")
  }

  private func expectScreen(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
    let label = app.staticTexts.matching(identifier: "currentScreen")
      .matching(NSPredicate(format: "label == %@", "screen: \(name)")).firstMatch
    XCTAssertTrue(label.waitForExistence(timeout: 5),
                  "expected screen \(name), got \(currentLabels())", file: file, line: line)
  }

  private func currentLabels() -> [String] {
    app.staticTexts.matching(identifier: "currentScreen").allElementsBoundByIndex.map(\.label)
  }
}
