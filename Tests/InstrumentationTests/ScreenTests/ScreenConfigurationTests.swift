/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

@testable import ScreenInstrumentation
import XCTest

final class ScreenConfigurationTests: XCTestCase {
  func testEverythingButSwiftUIDetectionIsEnabledByDefault() {
    let configuration = ScreenInstrumentationConfiguration()

    XCTAssertEqual(configuration.enabledSources, Set(ScreenSource.allCases).subtracting([.swiftUIHosting]))
    XCTAssertTrue(configuration.detectsUIKitScreensAutomatically)
    XCTAssertFalse(configuration.detectsSwiftUIScreensAutomatically)
    XCTAssertFalse(configuration.usesTitleForHostingControllers)
  }

  func testAutomaticSwiftUIDetectionCanBeTurnedOn() {
    let configuration = ScreenInstrumentationConfiguration(detectsSwiftUIScreensAutomatically: true)

    XCTAssertEqual(configuration.enabledSources, Set(ScreenSource.allCases))
  }

  func testAutomaticUIKitDetectionCanBeTurnedOffAlone() {
    let configuration = ScreenInstrumentationConfiguration(detectsUIKitScreensAutomatically: false,
                                                           detectsSwiftUIScreensAutomatically: true)

    XCTAssertEqual(configuration.enabledSources, Set(ScreenSource.allCases).subtracting([.uiKit]))
  }

  func testModifiersAndManualCallsStayEnabledWithoutAutomaticDetection() {
    let configuration = ScreenInstrumentationConfiguration(detectsUIKitScreensAutomatically: false,
                                                           detectsSwiftUIScreensAutomatically: false)

    XCTAssertEqual(configuration.enabledSources,
                   [.swiftUINavigation, .swiftUITabs, .swiftUIScreen, .manual])
  }

  func testAutomaticDetectionCanBeTurnedBackOn() {
    var configuration = ScreenInstrumentationConfiguration(detectsUIKitScreensAutomatically: false,
                                                           detectsSwiftUIScreensAutomatically: false)

    configuration.detectsUIKitScreensAutomatically = true
    configuration.detectsSwiftUIScreensAutomatically = true

    XCTAssertEqual(configuration.enabledSources, Set(ScreenSource.allCases))
  }
}
