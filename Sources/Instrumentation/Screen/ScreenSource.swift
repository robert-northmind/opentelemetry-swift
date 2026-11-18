/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// The mechanism that detected a screen. Each case can be enabled or disabled independently.
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
  /// Automatic and best-effort: `viewDidAppear` on the hosting controllers SwiftUI creates.
  case swiftUIHosting = "swiftui.hosting"

  var isExplicit: Bool {
    switch self {
    case .manual, .swiftUINavigation, .swiftUITabs, .swiftUIScreen: return true
    case .uiKit, .swiftUIHosting: return false
    }
  }
}

/// Identifies one tracked screen instance for the time it is visible.
public struct ScreenID: Hashable, Sendable {
  private enum Storage: Hashable, Sendable {
    case uuid(UUID)
    case object(ObjectIdentifier)
    case manual
  }

  private let storage: Storage

  public init() {
    storage = .uuid(UUID())
  }

  public init(object: AnyObject) {
    storage = .object(ObjectIdentifier(object))
  }

  private init(storage: Storage) {
    self.storage = storage
  }

  static let manual = ScreenID(storage: .manual)
}
