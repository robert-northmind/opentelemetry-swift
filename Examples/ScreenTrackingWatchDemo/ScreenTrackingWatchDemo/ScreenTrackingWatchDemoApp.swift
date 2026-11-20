/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import OpenTelemetryApi
import OpenTelemetrySdk
import ScreenInstrumentation
import SwiftUI

/// Screen tracking on watchOS. There is no UIKit, so screens are named only through the SwiftUI
/// modifiers and manual calls; automatic detection does not apply.
@main
struct ScreenTrackingWatchDemoApp: App {
  @StateObject private var store = EventStore()

  init() {
    let store = EventStore()
    _store = StateObject(wrappedValue: store)
    OpenTelemetry.registerLoggerProvider(
      loggerProvider: LoggerProviderBuilder()
        .with(processors: [ScreenLogRecordProcessor(nextProcessor: SimpleLogRecordProcessor(
          logRecordExporter: ScreenEventExporter { line in Task { @MainActor in store.append(line) } }
        ))])
        .build()
    )
    ScreenInstrumentation.install()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
    }
  }
}

/// The screen changes reported so far, newest last.
@MainActor
final class EventStore: ObservableObject {
  @Published private(set) var lines: [String] = []

  func append(_ line: String) {
    lines.append(line)
  }
}

enum WatchTab: String, Hashable {
  case workouts
  case manual
}

enum WorkoutRoute: Hashable {
  case workout(id: Int)
  case summary(workoutID: Int)
}

struct RootView: SwiftUI.View {
  @State private var tab = WatchTab.workouts

  var body: some SwiftUI.View {
    TabView(selection: $tab) {
      WorkoutsTab(tab: $tab).tag(WatchTab.workouts)
      ManualTab(tab: $tab).tag(WatchTab.manual)
    }
    .tabViewStyle(.verticalPage)
    .otelTrackTabs(selection: tab) { "Tab.\($0.rawValue)" }
  }
}

/// A `NavigationStack` with a typed path, named from its routes.
struct WorkoutsTab: SwiftUI.View {
  @Binding var tab: WatchTab
  @State private var path: [WorkoutRoute] = []
  @State private var showsSettings = false

  var body: some SwiftUI.View {
    NavigationStack(path: $path) {
      List {
        CurrentScreen()
        Button("Manual tab") { tab = .manual }
        NavigationLink("Workout 1", value: WorkoutRoute.workout(id: 1))
        Button("Settings") { showsSettings = true }
      }
      .navigationTitle("Workouts")
      .navigationDestination(for: WorkoutRoute.self) { route in
        switch route {
        case let .workout(id):
          List {
            CurrentScreen()
            NavigationLink("Summary", value: WorkoutRoute.summary(workoutID: id))
          }
          .navigationTitle("Workout \(id)")
        case .summary:
          List {
            CurrentScreen()
            Button("Pop to root") { path.removeAll() }
          }
          .navigationTitle("Summary")
        }
      }
    }
    .otelTrackNavigation(path: path, rootName: "Workouts")
    .sheet(isPresented: $showsSettings) {
      List {
        CurrentScreen()
        Button("Done") { showsSettings = false }
      }
      .otelScreen("Settings")
    }
  }
}

/// Manual calls, for screens none of the modifiers can see.
struct ManualTab: SwiftUI.View {
  @Binding var tab: WatchTab

  var body: some SwiftUI.View {
    List {
      CurrentScreen()
      Button("Workouts tab") { tab = .workouts }
      Button("Set manual screen") { ScreenTracker.shared.setScreen(name: "Manual") }
      Button("Clear manual screen") { ScreenTracker.shared.clearScreen() }
    }
  }
}

/// The current screen name and the number of screen changes, for people and UI tests.
struct CurrentScreen: SwiftUI.View {
  @EnvironmentObject private var store: EventStore

  var body: some SwiftUI.View {
    VStack(alignment: .leading) {
      Text("screen: \(store.lines.isEmpty ? "<none>" : ScreenTracker.shared.currentScreenName ?? "<none>")")
        .accessibilityIdentifier("currentScreen")
      Text("events: \(store.lines.count)")
        .accessibilityIdentifier("eventCount")
    }
    .font(.footnote.monospaced())
  }
}

/// Prints each screen change and passes it to the store.
final class ScreenEventExporter: LogRecordExporter, @unchecked Sendable {
  private let sink: @Sendable (String) -> Void

  init(sink: @escaping @Sendable (String) -> Void) {
    self.sink = sink
  }

  func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
    for record in logRecords where record.eventName == ScreenConstants.navigationCompleteEvent {
      let previous = record.attributes[ScreenConstants.previousScreenName]?.description ?? "<none>"
      let current = record.attributes[ScreenConstants.navigationDestinationName]?.description ?? "<none>"
      let source = record.attributes[ScreenConstants.screenSource]?.description ?? "<none>"
      let line = "\(previous) → \(current) [\(source)]"
      NSLog("[otel] %@", line)
      sink(line)
    }
    return .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {}

  func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
    .success
  }
}
