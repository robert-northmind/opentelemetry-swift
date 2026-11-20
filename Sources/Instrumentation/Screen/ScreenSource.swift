/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// The mechanism that detected a screen. Its raw value is reported as `app.screen.source` on the
/// `app.navigation.complete` event.
public enum ScreenSource: String, Sendable, CaseIterable, Hashable {
  /// `ScreenTracker.setScreen(name:)` called directly by the app.
  case manual
  /// Automatic: `viewDidAppear` on view controllers defined by the app.
  case uiKit = "uikit"
  /// `.otelTrackNavigation(path:)` on a `NavigationStack`.
  case swiftUINavigation = "swiftui.navigation"
  /// `.otelTrackTabs(selection:)` on a `TabView`.
  case swiftUITabs = "swiftui.tabs"
  /// `.otelScreen()` on an individual view.
  case swiftUIScreen = "swiftui.screen"
  /// Automatic: `viewDidAppear` on the hosting controllers SwiftUI creates for navigation
  /// destinations, presentations and tabs, named after the SwiftUI view they show.
  case swiftUIHosting = "swiftui.hosting"
}

/// Identifies one tracked screen instance for the time it is visible.
struct ScreenID: Hashable, Sendable {
  private enum Storage: Hashable, Sendable {
    case uuid(UUID)
    case object(ObjectIdentifier)
    case manual
  }

  private let storage: Storage

  init() {
    storage = .uuid(UUID())
  }

  init(object: AnyObject) {
    storage = .object(ObjectIdentifier(object))
  }

  private init(storage: Storage) {
    self.storage = storage
  }

  static let manual = ScreenID(storage: .manual)
}
