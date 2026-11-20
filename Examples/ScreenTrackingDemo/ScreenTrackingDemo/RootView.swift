/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI

enum DemoTab: String, Hashable {
  case stack
  case links
  case modals
  case uiKit
  case inspector
}

struct RootView: View {
  @State private var tab = DemoTab.stack

  var body: some View {
    VStack(spacing: 0) {
      HeadsUpDisplay()
      TabView(selection: $tab) {
        StackTab()
          .tabItem { Label("Stack", systemImage: "square.stack.3d.up") }
          .tag(DemoTab.stack)
        LinksTab()
          .tabItem { Label("Links", systemImage: "link") }
          .tag(DemoTab.links)
        ModalsTab()
          .tabItem { Label("Modals", systemImage: "rectangle.on.rectangle") }
          .tag(DemoTab.modals)
        UIKitTab()
          .tabItem { Label("UIKit", systemImage: "hammer") }
          .tag(DemoTab.uiKit)
        InspectorTab()
          .tabItem { Label("Inspector", systemImage: "waveform.path.ecg") }
          .tag(DemoTab.inspector)
      }
      // Layer 3: one line on the TabView tracks every tab switch.
      .applying(DemoSettings.appliesTrackTabs) { $0.otelTrackTabs(selection: tab) { "Tab.\($0.rawValue)" } }
    }
  }
}

extension View {
  /// Applies `transform` only when `condition` holds, so the demo can run without a modifier.
  @ViewBuilder
  func applying(_ condition: Bool, _ transform: (Self) -> some View) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}

/// Always-visible strip showing what the instrumentation currently believes.
struct HeadsUpDisplay: View {
  @EnvironmentObject private var store: EventStore

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("screen: \(ScreenTracker.shared.currentScreenName ?? "<none>")")
        .font(.caption.monospaced().bold())
      Text(lastTransition)
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.thinMaterial)
    .accessibilityIdentifier("headsUpDisplay")
  }

  private var lastTransition: String {
    guard let event = store.lastScreenView else { return "no screen-view event yet" }
    return "\(event.title)  (\(event.detail))"
  }
}

/// Explains what a demo screen exercises and what to look for in the heads-up display.
struct Explanation: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(.secondary)
  }
}
