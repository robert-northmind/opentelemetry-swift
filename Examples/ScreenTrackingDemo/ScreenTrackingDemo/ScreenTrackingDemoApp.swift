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
    Telemetry.setUp { event in
      Task { @MainActor in store.append(event) }
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
    }
  }
}

/// Holds the telemetry shown in the heads-up display and on the Inspector tab.
@MainActor
final class EventStore: ObservableObject {
  @Published private(set) var events: [DemoEvent] = []
  @Published var enabledSources: Set<ScreenSource> = SourceSettings.load() {
    didSet {
      SourceSettings.save(enabledSources)
      ScreenInstrumentation.setEnabledSources(enabledSources)
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
