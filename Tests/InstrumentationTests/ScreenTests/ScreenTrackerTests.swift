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

  func testUIKitReportIsNotSuppressedByExplicitReport() {
    let fixture = TrackerFixture()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "detail", source: .swiftUINavigation)
    fixture.settle()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "LegacyViewController", source: .uiKit)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "LegacyViewController")
    XCTAssertEqual(fixture.transitions.last, Transition("detail", "LegacyViewController", .uiKit))
  }

  func testHostingReportRightAfterExplicitReportIsAccepted() {
    // Hosting controllers that an explicit modifier names are claimed by the modifier and
    // never reported; any other hosting controller is a screen of its own, however soon after
    // an explicit report it appears.
    let fixture = TrackerFixture()

    fixture.tracker.screenAppeared(id: ScreenID(), name: "Redirect", source: .swiftUIScreen)
    fixture.tracker.screenAppeared(id: ScreenID(), name: "PlainView", source: .swiftUIHosting)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "PlainView")
  }

  // MARK: Returning to a screen

  func testReappearingScreenWaitsUntilTheScreenOnTopDisappears() {
    // SwiftUI calls onAppear on the screen underneath when a back navigation starts, and
    // onDisappear on the screen on top when it ends.
    let fixture = TrackerFixture()
    let list = ScreenID()
    let detail = ScreenID()
    fixture.tracker.screenAppeared(id: list, name: "List", source: .swiftUIScreen)
    fixture.settle()
    fixture.tracker.screenAppeared(id: detail, name: "Detail", source: .swiftUIScreen)
    fixture.tracker.screenDisappeared(id: list)
    fixture.settle()

    fixture.tracker.report(id: list, name: "List", source: .swiftUIScreen, isReappearing: true)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Detail")

    fixture.tracker.screenDisappeared(id: detail)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "List")
    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "List", .swiftUIScreen),
      Transition("List", "Detail", .swiftUIScreen),
      Transition("Detail", "List", .swiftUIScreen)
    ])
  }

  func testCancelledBackSwipeEmitsNothing() {
    let fixture = TrackerFixture()
    let list = ScreenID()
    fixture.tracker.screenAppeared(id: list, name: "List", source: .swiftUIScreen)
    fixture.settle()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Detail", source: .swiftUIScreen)
    fixture.tracker.screenDisappeared(id: list)
    fixture.settle()

    fixture.tracker.report(id: list, name: "List", source: .swiftUIScreen, isReappearing: true)
    fixture.settle()
    fixture.tracker.screenDisappeared(id: list)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Detail")
    XCTAssertEqual(fixture.transitions.count, 2)
  }

  func testReappearingScreenBecomesCurrentWhenNothingIsShown() {
    let fixture = TrackerFixture()

    fixture.tracker.report(id: ScreenID(), name: "Home", source: .swiftUIScreen, isReappearing: true)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [Transition(nil, "Home", .swiftUIScreen)])
  }

  // MARK: Containers

  func testReappearingContainerDoesNotReplaceTheScreenShown() {
    // A tab bar hidden by a full-screen presentation calls onAppear as soon as the dismissal
    // starts; the view controller underneath only appears once it has finished.
    let fixture = TrackerFixture()
    let tabs = ScreenID()
    let menu = ScreenID(object: NSObject())
    let cover = ScreenID()
    fixture.tracker.report(id: tabs, name: "Tab.settings", source: .swiftUITabs, isContainer: true)
    fixture.tracker.screenAppeared(id: menu, name: "Menu", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenAppeared(id: cover, name: "Cover", source: .uiKit)
    fixture.tracker.screenDisappeared(id: menu, isCovered: true)
    fixture.tracker.screenDisappeared(id: tabs)
    fixture.settle()

    fixture.tracker.report(id: tabs, name: "Tab.settings", source: .swiftUITabs,
                           isReappearing: true, isContainer: true)
    fixture.settle()
    fixture.tracker.screenAppeared(id: menu, name: "Menu", source: .uiKit)
    fixture.tracker.screenDisappeared(id: cover)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Menu", .uiKit),
      Transition("Menu", "Cover", .uiKit),
      Transition("Cover", "Menu", .uiKit)
    ])
  }

  func testReappearingScreenReplacesContainer() {
    // Switching back to a tab: the tab is reported first, then its screen appears again.
    let fixture = TrackerFixture()
    let links = ScreenID()
    fixture.tracker.report(id: ScreenID(), name: "Tab.links", source: .swiftUITabs, isContainer: true)
    fixture.tracker.report(id: links, name: "Links", source: .swiftUIScreen, isReappearing: true)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [Transition(nil, "Links", .swiftUIScreen)])
  }

  func testNewContainerReportReplacesScreen() {
    let fixture = TrackerFixture()
    let tabs = ScreenID()
    fixture.tracker.report(id: tabs, name: "Tab.home", source: .swiftUITabs, isContainer: true)
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .swiftUIScreen)
    fixture.settle()

    fixture.tracker.report(id: tabs, name: "Tab.inbox", source: .swiftUITabs, isContainer: true)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Tab.inbox")
  }

  // MARK: Covered screens

  func testScreenCoveredByUntrackedScreenKeepsItsName() {
    let fixture = TrackerFixture()
    let menu = ScreenID(object: NSObject())
    fixture.tracker.report(id: ScreenID(), name: "Tab.settings", source: .swiftUITabs, isContainer: true)
    fixture.tracker.screenAppeared(id: menu, name: "Menu", source: .uiKit)
    fixture.settle()

    fixture.tracker.screenDisappeared(id: menu, isCovered: true)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Menu")
    XCTAssertEqual(fixture.transitions, [Transition(nil, "Menu", .uiKit)])
  }

  func testDismissingSheetOverUntrackedScreenRestoresCoveredName() {
    let fixture = TrackerFixture()
    let menu = ScreenID(object: NSObject())
    let sheet = ScreenID()
    fixture.tracker.report(id: ScreenID(), name: "Tab.settings", source: .swiftUITabs, isContainer: true)
    fixture.tracker.screenAppeared(id: menu, name: "Menu", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenDisappeared(id: menu, isCovered: true)
    fixture.settle()

    fixture.tracker.screenAppeared(id: sheet, name: "Sheet", source: .swiftUIScreen)
    fixture.settle()
    fixture.tracker.screenDisappeared(id: sheet)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Menu")
  }

  func testCoveredScreenShownAgainIsNotCoveredAnyMore() {
    let fixture = TrackerFixture()
    let menu = ScreenID(object: NSObject())
    let detail = ScreenID(object: NSObject())
    fixture.tracker.report(id: ScreenID(), name: "Tab.settings", source: .swiftUITabs, isContainer: true)
    fixture.tracker.screenAppeared(id: menu, name: "Menu", source: .uiKit)
    fixture.settle()
    fixture.tracker.screenDisappeared(id: menu, isCovered: true)
    fixture.tracker.screenAppeared(id: detail, name: "Detail", source: .uiKit)
    fixture.settle()

    fixture.tracker.screenDisappeared(id: detail)
    fixture.tracker.screenAppeared(id: menu, name: "Menu", source: .uiKit)
    fixture.settle()

    XCTAssertEqual(fixture.transitions, [
      Transition(nil, "Menu", .uiKit),
      Transition("Menu", "Detail", .uiKit),
      Transition("Detail", "Menu", .uiKit)
    ])
  }

  func testClosedScreenRevealsContainer() {
    // A tracked screen closed without anything known replacing it: the tab is what is left.
    let fixture = TrackerFixture()
    let sheet = ScreenID()
    fixture.tracker.report(id: ScreenID(), name: "Tab.inbox", source: .swiftUITabs, isContainer: true)
    fixture.settle()
    fixture.tracker.screenAppeared(id: sheet, name: "Compose", source: .swiftUIScreen)
    fixture.settle()

    fixture.tracker.screenDisappeared(id: sheet)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Tab.inbox")
  }

  func testReappearingScreenReplacesCoveredScreen() {
    // Switching tabs without .otelTrackTabs: the other tab's screen is hidden (not closed) and
    // the explicit screen of this tab appears again. Both orders happen.
    for coveredFirst in [true, false] {
      let fixture = TrackerFixture()
      let home = ScreenID()
      let menu = ScreenID(object: NSObject())
      fixture.tracker.screenAppeared(id: home, name: "Home", source: .swiftUIScreen)
      fixture.settle()
      fixture.tracker.screenDisappeared(id: home)
      fixture.tracker.screenAppeared(id: menu, name: "Menu", source: .uiKit)
      fixture.settle()

      if coveredFirst {
        fixture.tracker.screenDisappeared(id: menu, isCovered: true)
        fixture.tracker.report(id: home, name: "Home", source: .swiftUIScreen, isReappearing: true)
      } else {
        fixture.tracker.report(id: home, name: "Home", source: .swiftUIScreen, isReappearing: true)
        fixture.tracker.screenDisappeared(id: menu, isCovered: true)
      }
      fixture.settle()

      XCTAssertEqual(fixture.tracker.currentScreenName, "Home", "covered first: \(coveredFirst)")
      XCTAssertEqual(fixture.transitions.last, Transition("Menu", "Home", .swiftUIScreen))
    }
  }

  func testDeadScreenIsDroppedInsteadOfRevealed() {
    // A view controller removed from a navigation stack while covered (popToRoot,
    // setViewControllers) never reports disappearing.
    let fixture = TrackerFixture()
    let alive = AliveFlag()
    let middle = ScreenID(object: NSObject())
    let sheet = ScreenID()
    fixture.tracker.report(id: ScreenID(), name: "Tab.shop", source: .swiftUITabs, isContainer: true)
    fixture.tracker.report(id: middle, name: "Middle", source: .uiKit, isAlive: { alive.value })
    fixture.settle()
    fixture.tracker.screenDisappeared(id: middle, isCovered: true)
    fixture.tracker.screenAppeared(id: sheet, name: "Sheet", source: .swiftUIScreen)
    fixture.settle()

    alive.value = false
    fixture.tracker.screenDisappeared(id: sheet)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Tab.shop")
  }

  func testClosingAWindowRevealsAScreenOfTheOtherWindow() {
    // Screens in a window that is closed get no disappearance callbacks.
    let fixture = TrackerFixture()
    let otherWindowIsOpen = AliveFlag()
    fixture.tracker.report(id: ScreenID(), name: "Tab.inspector", source: .swiftUITabs, isContainer: true)
    fixture.tracker.report(id: ScreenID(), name: "InspectorView", source: .swiftUIScreen)
    fixture.tracker.report(id: ScreenID(), name: "product", source: .swiftUINavigation,
                           isAlive: { otherWindowIsOpen.value })
    fixture.settle()
    XCTAssertEqual(fixture.tracker.currentScreenName, "product")

    otherWindowIsOpen.value = false
    fixture.tracker.revalidate()
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "InspectorView")
    XCTAssertEqual(fixture.transitions.last?.from, "product")
  }

  func testRevalidatingWithEveryScreenAliveChangesNothing() {
    let fixture = TrackerFixture()
    fixture.tracker.report(id: ScreenID(), name: "Home", source: .swiftUIScreen, isAlive: { true })
    fixture.settle()

    fixture.tracker.revalidate()
    fixture.settle()

    XCTAssertEqual(fixture.transitions.count, 1)
  }

  func testDisablingTheCurrentScreensSourceRevealsTheScreenUnderneath() {
    let fixture = TrackerFixture()
    fixture.tracker.report(id: ScreenID(), name: "Tab.inspector", source: .swiftUITabs, isContainer: true)
    fixture.tracker.screenAppeared(id: ScreenID(), name: "InspectorView", source: .swiftUIHosting)
    fixture.settle()

    fixture.tracker.enabledSources.remove(.swiftUIHosting)
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Tab.inspector")
    XCTAssertEqual(fixture.transitions.last, Transition("InspectorView", "Tab.inspector", .swiftUITabs))
  }

  func testManualScreenCanBeCleared() {
    let fixture = TrackerFixture()
    fixture.tracker.screenAppeared(id: ScreenID(), name: "Home", source: .uiKit)
    fixture.tracker.setScreen(name: "Onboarding")
    fixture.settle()

    fixture.tracker.clearScreen()
    fixture.settle()

    XCTAssertEqual(fixture.tracker.currentScreenName, "Home")
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

private final class AliveFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = true

  var value: Bool {
    get { lock.withLock { storage } }
    set { lock.withLock { storage = newValue } }
  }
}
