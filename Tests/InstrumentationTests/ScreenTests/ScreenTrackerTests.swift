/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import XCTest
@testable import ScreenInstrumentation

final class ScreenTrackerTests: XCTestCase {
  func testNoCurrentScreenBeforeFirstReport() {
    let fixture = TrackerFixture()

    fixture.settle()

    XCTAssertNil(fixture.tracker.currentScreenName)
    XCTAssertEqual(fixture.transitions, [])
  }

  func testCurrentScreenChangesImmediatelyButEventWaitsForNextTurn() {
    let fixture = TrackerFixture()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .uiKit)

    XCTAssertEqual(fixture.tracker.currentScreenName, "Home")
    XCTAssertEqual(fixture.transitions, [])

    fixture.settle()

    XCTAssertEqual(fixture.transitions, [Transition(nil, "Home", .uiKit)])
  }

  func testNewScreenEmitsEventWithPrevious() {
    let fixture = TrackerFixture()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Detail", source: .swiftUIScreen)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Detail")
    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Home", .uiKit),
      Transition("Home", "Detail", .swiftUIScreen)
    ])
  }

  func testReportsInTheSameTurnCollapseIntoOneEvent() {
    let fixture = TrackerFixture()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .uiKit)
    fixture.settle()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "Tab.shop", source: .swiftUITabs)
    fixture.tracker.screenAppeared(id: ScreenID(), name: "ProductList", source: .swiftUINavigation)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Home", .uiKit),
      Transition("Home", "ProductList", .swiftUINavigation)
    ])
  }

  func testReturningToTheSameScreenWithinOneTurnEmitsNothing() {
    let fixture = TrackerFixture()
    let home = ScreenID()
    fixture.tracker.screenAppeared(id: home, name: "Home", source: .uiKit)
    fixture.settle()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "Flash", source: .uiKit)
    fixture.tracker.screenAppeared(id: home, name: "Home", source: .uiKit)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [Transition(nil, "Home", .uiKit)])
  }

  func testSameNameReportedAgainEmitsNothing() {
    let fixture = TrackerFixture()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .swiftUIScreen)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [Transition(nil, "Home", .uiKit)])
  }

  func testPushDoesNotFlashTheScreenUnderneath() {
    let fixture = TrackerFixture()
    let first = ScreenID()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Root", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenAppeared(id: first, name: "First", source: .uiKit)
    fixture.settle()

    fixture.tracker.screenDisappeared(id: first)
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Second", source: .uiKit)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Second")
    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Root", .uiKit),
      Transition("Root", "First", .uiKit),
      Transition("First", "Second", .uiKit)
    ])
  }

  func testDismissedSheetRestoresScreenUnderneath() {
    let fixture = TrackerFixture()
    let sheet = ScreenID()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .swiftUINavigation)
    fixture.settle()
    fixture.tracker.screenAppeared(id: sheet, name: "Sheet", source: .swiftUIScreen)
    fixture.settle()

    fixture.tracker.screenDisappeared(id: sheet)

    XCTAssertEqual(fixture.tracker.currentScreenName, "Sheet", "restoring waits for the next turn")

    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Home")
    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Home", .swiftUINavigation),
      Transition("Home", "Sheet", .swiftUIScreen),
      Transition("Sheet", "Home", .swiftUINavigation)
    ])
  }

  func testLastScreenDisappearingKeepsLastKnownName() {
    let fixture = TrackerFixture()
    let only = ScreenID()

    fixture.tracker.screenAppeared(id: only, name: "Home", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenDisappeared(id: only)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Home")
    XCTAssertEqual(fixture.transitions, [Transition(nil, "Home", .uiKit)])
  }

  func testNonCurrentScreenDisappearingChangesNothing() {
    let fixture = TrackerFixture()
    let underneath = ScreenID()
    fixture.tracker.screenAppeared(id: underneath, name: "Home", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Sheet", source: .uiKit)
    fixture.settle()

    fixture.tracker.screenDisappeared(id: underneath)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Sheet")
    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Home", .uiKit),
      Transition("Home", "Sheet", .uiKit)
    ])
  }

  func testSameIDReportedWithNewNameUpdatesScreen() {
    let fixture = TrackerFixture()
    let stack = ScreenID()

    fixture.tracker.screenAppeared(id: stack, name: "List", source: .swiftUINavigation)
    fixture.settle()
    fixture.tracker.screenAppeared(id: stack, name: "detail", source: .swiftUINavigation)
    fixture.settle()
    fixture.tracker.screenDisappeared(id: stack)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "detail", "the stack holds one entry per id")
    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "List", .swiftUINavigation),
      Transition("List", "detail", .swiftUINavigation)
    ])
  }

  func testEventTimestampIsWhenTheScreenAppeared() {
    let fixture = TrackerFixture()
    let appearedAt = fixture.clock.now

    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .uiKit)
    fixture.clock.advance(by: 5)
    fixture.settle()

    XCTAssertEqual(fixture.exporter.records.map(\.timestamp), [appearedAt])
  }

  func testDisabledSourceIsIgnored() {
    let fixture = TrackerFixture()
    fixture.tracker.enabledSources = [.swiftUIScreen]

    fixture.tracker.screenAppeared(id: ScreenID(), name: "HomeViewController", source: .uiKit)
    fixture.settle()

    XCTAssertNil(fixture.tracker.currentScreenName)
    XCTAssertEqual(fixture.transitions, [])
  }

  func testDisablingSourceDropsItsScreensFromTheStack() {
    let fixture = TrackerFixture()
    let sheet = ScreenID()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "HomeViewController", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenAppeared(id: sheet, name: "Sheet", source: .swiftUIScreen)
    fixture.settle()

    fixture.tracker.enabledSources = [.swiftUIScreen]
    fixture.tracker.screenDisappeared(id: sheet)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Sheet", "nothing is left to restore")
  }

  func testSetScreenReportsManualSource() {
    let fixture = TrackerFixture()

    fixture.tracker.setScreen(name: "Checkout")
    fixture.settle()
    fixture.tracker.setScreen(name: "Confirmation")
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Checkout", .manual),
      Transition("Checkout", "Confirmation", .manual)
    ])
  }

  func testHostingReportIsSuppressedRightAfterExplicitReport() {
    let fixture = TrackerFixture()
    fixture.tracker.hostingSuppressionInterval = 1

    fixture.tracker.screenAppeared(id: ScreenID(), name: "detail", source: .swiftUINavigation)
    fixture.settle()
    fixture.clock.advance(by: 0.5)
    fixture.tracker.screenAppeared(id: ScreenID(), name: "DetailView", source: .swiftUIHosting)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "detail")
    XCTAssertEqual(fixture.transitions, [Transition(nil, "detail", .swiftUINavigation)])
  }

  func testHostingReportIsAcceptedOnceSuppressionIntervalPassed() {
    let fixture = TrackerFixture()
    fixture.tracker.hostingSuppressionInterval = 1

    fixture.tracker.screenAppeared(id: ScreenID(), name: "detail", source: .swiftUINavigation)
    fixture.settle()
    fixture.clock.advance(by: 1.5)
    fixture.tracker.screenAppeared(id: ScreenID(), name: "SheetView", source: .swiftUIHosting)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "detail", .swiftUINavigation),
      Transition("detail", "SheetView", .swiftUIHosting)
    ])
  }

  func testUIKitReportIsNotSuppressedByExplicitReport() {
    let fixture = TrackerFixture()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "detail", source: .swiftUINavigation)
    fixture.settle()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "LegacyViewController", source: .uiKit)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "LegacyViewController")
    XCTAssertEqual(fixture.transitions.last, Transition("detail", "LegacyViewController", .uiKit))
  }

  func testConcurrentReportsLeaveAConsistentEventChain() {
    let fixture = TrackerFixture()
    let tracker = fixture.tracker
    let scheduler = fixture.scheduler

    DispatchQueue.concurrentPerform(iterations: 200) { index in
      let id = ScreenID()
      tracker.screenAppeared(id: id, name: "Screen\(index % 7)", source: .manual)
      tracker.screenDisappeared(id: id)
      scheduler.runPending()
    }
    fixture.settle()

    let transitions = fixture.transitions
    XCTAssertFalse(transitions.isEmpty)
    XCTAssertNil(transitions.first?.from)
    for (earlier, later) in zip(transitions, transitions.dropFirst()) {
      XCTAssertEqual(later.from, earlier.to, "each event starts where the previous one ended")
      XCTAssertNotEqual(later.from, later.to)
    }
    XCTAssertEqual(transitions.last?.to, tracker.currentScreenName)
  }
}
