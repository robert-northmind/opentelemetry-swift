/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI

/// Switches detection mechanisms on and off and shows everything the SDK emitted.
struct InspectorTab: View {
  @EnvironmentObject private var store: EventStore

  private struct Preset: Identifiable {
    let id: String
    let sources: Set<ScreenSource>
  }

  private let presets = [
    Preset(id: "Default", sources: ScreenInstrumentationConfiguration().enabledSources),
    Preset(id: "Automatic only", sources: [.uiKit, .swiftUIHosting]),
    Preset(id: "Containers only", sources: [.swiftUINavigation, .swiftUITabs]),
    Preset(id: "Per-screen only", sources: [.swiftUIScreen]),
    Preset(id: "Everything", sources: Set(ScreenSource.allCases)),
    Preset(id: "Nothing", sources: [])
  ]

  var body: some View {
    NavigationStack {
      List {
        Section("Detection mechanisms") {
          sourceToggle(.uiKit, "UIKit view controllers", "Layer 2, automatic")
          sourceToggle(.swiftUINavigation, ".otelTrackNavigation", "Layer 3, one line per stack")
          sourceToggle(.swiftUITabs, ".otelTrackTabs", "Layer 3, one line per TabView")
          sourceToggle(.swiftUIScreen, ".otelScreen", "Layer 4, one line per screen")
          sourceToggle(.swiftUIHosting, "SwiftUI hosting controllers", "Layer 5, automatic, experimental")
          sourceToggle(.manual, "ScreenTracker.setScreen", "Manual calls")
        }
        Section("Presets") {
          ForEach(presets) { preset in
            Button(preset.id) { store.enabledSources = preset.sources }
          }
        }
        Section("Actions") {
          Button("Emit a span and a log record") { Telemetry.emitSampleSpanAndLog() }
          Button("Call setScreen(\"ManualScreen\")") { ScreenTracker.shared.setScreen(name: "ManualScreen") }
          Button("Clear log", role: .destructive) { store.clear() }
        }
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

  private func sourceToggle(_ source: ScreenSource, _ title: String, _ subtitle: String) -> some View {
    Toggle(isOn: Binding(
      get: { store.enabledSources.contains(source) },
      set: { isOn in
        if isOn {
          store.enabledSources.insert(source)
        } else {
          store.enabledSources.remove(source)
        }
      }
    )) {
      VStack(alignment: .leading) {
        Text(title)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
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
