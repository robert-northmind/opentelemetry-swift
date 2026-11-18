/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI

/// Classic `NavigationLink(destination:)` navigation, where no path exists to observe.
///
/// Layer 4: screens opt in with `.otelScreen()`. The screens without it are only seen by
/// layer 5 (automatic hosting-controller detection), so they show what that layer can recover.
struct LinksTab: View {
  var body: some View {
    NavigationStack {
      List {
        Section {
          Explanation("NavigationLink(destination:) without a path. Compare screens that carry "
            + ".otelScreen() with screens that rely on automatic detection.")
        }
        Section("With .otelScreen()") {
          NavigationLink("Default name (from view type)") {
            ArticleView().otelScreen()
          }
          NavigationLink("Explicit name") {
            ArticleView().otelScreen("Article.Explicit")
          }
          NavigationLink("Modifier inside the view body") {
            SelfTrackingView()
          }
        }
        Section("Without any modifier") {
          NavigationLink("Plain view with a navigation title") {
            UntrackedTitledView()
          }
          NavigationLink("Plain view without a title") {
            UntrackedUntitledView()
          }
          NavigationLink("Type-erased with AnyView") {
            AnyView(UntrackedTitledView())
          }
        }
        Section("Nested") {
          NavigationLink("Three levels deep") {
            DeepView(level: 1)
          }
        }
      }
      .navigationTitle("Links")
      .otelScreen("LinksRoot")
    }
  }
}

struct ArticleView: View {
  var body: some View {
    List {
      Explanation("Tracked by .otelScreen() applied at the call site.")
    }
    .navigationTitle("Article")
  }
}

struct SelfTrackingView: View {
  var body: some View {
    List {
      Explanation("Tracked by .otelScreen() at the end of its own body, so the default name "
        + "has to be recovered from a ModifiedContent type.")
    }
    .navigationTitle("Self tracking")
    .otelScreen()
  }
}

struct UntrackedTitledView: View {
  var body: some View {
    List {
      Explanation("No modifier. Only automatic detection can see this screen. It has a "
        + "navigation title that can serve as a fallback name.")
    }
    .navigationTitle("Untracked titled")
  }
}

struct UntrackedUntitledView: View {
  var body: some View {
    List {
      Explanation("No modifier and no navigation title. Automatic detection has only the "
        + "hosting controller's type to go on.")
    }
  }
}

struct DeepView: View {
  let level: Int

  var body: some View {
    List {
      Text("Level \(level)")
      if level < 3 {
        NavigationLink("Go deeper") {
          DeepView(level: level + 1)
        }
      }
    }
    .navigationTitle("Level \(level)")
    .otelScreen("Deep.Level\(level)")
  }
}
