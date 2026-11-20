/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI

/// Classic `NavigationLink(destination:)` navigation, where no path exists to observe.
///
/// Screens with `.otelScreen()` are named explicitly. The others are only seen by automatic
/// hosting-controller detection, which names them after their view type.
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
          NavigationLink("Tracked screen that blocks the main thread") {
            SlowView().otelScreen("Slow")
          }
          NavigationLink("Tracked screen that redirects to a plain one") {
            RedirectingView()
          }
        }
        Section("Window") {
          Button("Sign out (replaces the window's root view controller)") {
            SignedOutViewController.signOut()
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
      Explanation("Tracked by .otelScreen(\"SelfTracking\") at the end of its own body. Inside a "
        + "body the modifier sees the List, not SelfTrackingView, so it is given a name.")
    }
    .navigationTitle("Self tracking")
    .otelScreen("SelfTracking")
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

/// Does a second of work on the main thread when it appears, which delays the end of the push
/// transition.
struct SlowView: View {
  var body: some View {
    List {
      Explanation("Blocks the main thread for 1.2 seconds when it appears. It should still be "
        + "reported once, as \"Slow\".")
    }
    .navigationTitle("Slow")
    .onAppear {
      // Heavy work started on appear, which runs while the push transition is under way.
      DispatchQueue.main.async { Thread.sleep(forTimeInterval: 1.2) }
    }
  }
}

/// A tracked screen that immediately pushes an untracked one, like a deep link or an
/// onboarding redirect. The pushed screen is only visible to automatic detection.
struct RedirectingView: View {
  @State private var showsNext = false
  @State private var hasRedirected = false

  var body: some View {
    List {
      Explanation("Tracked as \"Redirect\". Pushes UntrackedUntitledView 0.3 seconds after "
        + "appearing.")
    }
    .navigationTitle("Redirect")
    .otelScreen("Redirect")
    .navigationDestination(isPresented: $showsNext) {
      UntrackedUntitledView()
    }
    .task {
      guard !hasRedirected else { return }
      hasRedirected = true
      try? await Task.sleep(nanoseconds: 300_000_000)
      showsNext = true
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
