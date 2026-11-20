/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI

@main
struct ScreenTrackingDemoApp: App {
  @StateObject private var store: EventStore

  init() {
    let store = EventStore()
    _store = StateObject(wrappedValue: store)
    let otherRUMOrder = OtherRUMTool.configuredOrder
    if otherRUMOrder == .before {
      OtherRUMTool.start()
    }
    Telemetry.setUp { event in
      Task { @MainActor in store.append(event) }
    }
    if otherRUMOrder == .after {
      OtherRUMTool.start()
    }
  }

  var body: some Scene {
    WindowGroup(id: "main") {
      RootView()
        .environmentObject(store)
    }
  }
}

/// Holds the telemetry shown in the heads-up display and on the Inspector tab.
@MainActor
final class EventStore: ObservableObject {
  @Published private(set) var events: [DemoEvent] = []
  @Published var detectsUIKitScreens = DemoSettings.detectsUIKitScreens {
    didSet {
      DemoSettings.detectsUIKitScreens = detectsUIKitScreens
      ScreenInstrumentation.setDetectsUIKitScreensAutomatically(detectsUIKitScreens)
    }
  }

  @Published var detectsSwiftUIScreens = DemoSettings.detectsSwiftUIScreens {
    didSet {
      DemoSettings.detectsSwiftUIScreens = detectsSwiftUIScreens
      ScreenInstrumentation.setDetectsSwiftUIScreensAutomatically(detectsSwiftUIScreens)
    }
  }

  var lastScreenView: DemoEvent? {
    events.last { $0.kind == .screenView }
  }

  func append(_ event: DemoEvent) {
    events.append(event)
  }

  func clear() {
    events.removeAll()
  }
}
