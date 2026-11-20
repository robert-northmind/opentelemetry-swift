/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI
import UIKit

/// Switches automatic detection and the demo's modifiers on and off, and shows everything the SDK
/// emitted.
struct InspectorTab: View {
  @EnvironmentObject private var store: EventStore
  @Environment(\.openWindow) private var openWindow
  @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
  @State private var otherRUMRefresh = 0

  var body: some View {
    NavigationStack {
      List {
        Section {
          Toggle(isOn: $store.detectsUIKitScreens) {
            labeled("UIKit view controllers", "detectsUIKitScreensAutomatically")
          }
          Toggle(isOn: $store.detectsSwiftUIScreens) {
            labeled("SwiftUI hosting controllers", "detectsSwiftUIScreensAutomatically")
          }
        } header: {
          Text("Automatic detection")
        } footer: {
          Text("SDK settings, applied at once. The modifiers and setScreen always report when they are used.")
        }
        Section {
          Toggle(isOn: Binding(get: { DemoSettings.appliesTrackTabs },
                               set: { DemoSettings.appliesTrackTabs = $0; otherRUMRefresh += 1 })) {
            labeled("Apply .otelTrackTabs", "On the TabView")
          }
          Toggle(isOn: Binding(get: { DemoSettings.appliesTrackNavigation },
                               set: { DemoSettings.appliesTrackNavigation = $0; otherRUMRefresh += 1 })) {
            labeled("Apply .otelTrackNavigation", "On the Stack tab's NavigationStack")
          }
        } header: {
          Text("Modifiers in this demo")
        } footer: {
          Text("Shows what automatic detection does without them. Applies on the next launch.")
        }
        .id(otherRUMRefresh)
        Section("Export") {
          NavigationLink {
            ExportSettingsView()
          } label: {
            labeled("OTLP export", Telemetry.exportDescription)
          }
        }
        Section("Actions") {
          Button("Emit a span and a log record") { Telemetry.emitSampleSpanAndLog() }
          Button("Call setScreen(\"ManualScreen\")") { ScreenTracker.shared.setScreen(name: "ManualScreen") }
          Button("Call clearScreen()") { ScreenTracker.shared.clearScreen() }
          if supportsMultipleWindows {
            Button("Open a new window") { openWindow(id: "main") }
            if #available(iOS 17, *) {
              CloseWindowButton()
            }
          }
          Button("Clear log", role: .destructive) { store.clear() }
        }
        Section {
          Picker("Start at launch", selection: Binding(
            get: { OtherRUMTool.configuredOrder },
            set: { OtherRUMTool.setConfiguredOrder($0); otherRUMRefresh += 1 }
          )) {
            Text("Off").tag(OtherRUMTool.InstallOrder.off)
            Text("Before OTel").tag(OtherRUMTool.InstallOrder.before)
            Text("After OTel").tag(OtherRUMTool.InstallOrder.after)
          }
          LabeledContent("Status",
                         value: OtherRUMTool.isRunning ? "running, \(OtherRUMTool.appearCount) appearances" : "stopped")
          Button("Start other RUM tool now") { OtherRUMTool.start(); otherRUMRefresh += 1 }
          Button("Stop other RUM tool (unswizzle)") { OtherRUMTool.stop(); otherRUMRefresh += 1 }
        } header: {
          Text("Other RUM tool")
        } footer: {
          Text("Hooks viewDidAppear and viewDidDisappear the way some RUM SDKs do. The launch order applies on the next launch.")
        }
        .id(otherRUMRefresh)
        Section("Telemetry (newest first, \(store.events.count))") {
          ForEach(store.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 2) {
              Text(event.title)
                .font(.footnote.monospaced())
                .foregroundStyle(color(for: event.kind))
              Text("\(event.time.formatted(date: .omitted, time: .standard))  \(event.detail)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Inspector")
    }
  }

  private func labeled(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading) {
      Text(title)
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func color(for kind: DemoEvent.Kind) -> Color {
    switch kind {
    case .screenView: return .primary
    case .log: return .blue
    case .span: return .purple
    }
  }
}

@available(iOS 17, *)
private struct CloseWindowButton: View {
  @Environment(\.dismissWindow) private var dismissWindow
  @State private var scene: UIWindowScene?

  var body: some View {
    Button("Close this window") { dismissWindow() }
    // Leaves time to navigate elsewhere in this window, to see which screen is current after it
    // closes.
    Button("Close this window in 5 seconds") {
      guard let session = scene?.session else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
      }
    }
    .background(WindowSceneReader { scene = $0 })
  }
}

/// Reports the window scene the view is shown in.
private struct WindowSceneReader: UIViewRepresentable {
  let onScene: (UIWindowScene?) -> Void

  func makeUIView(context: Context) -> SceneView {
    SceneView(onScene: onScene)
  }

  func updateUIView(_ view: SceneView, context: Context) {}

  final class SceneView: UIView {
    let onScene: (UIWindowScene?) -> Void

    init(onScene: @escaping (UIWindowScene?) -> Void) {
      self.onScene = onScene
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      let scene = window?.windowScene
      DispatchQueue.main.async { self.onScene(scene) }
    }
  }
}
