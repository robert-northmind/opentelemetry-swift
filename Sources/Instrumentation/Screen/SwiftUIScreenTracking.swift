/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if canImport(SwiftUI)
  import SwiftUI

  public extension View {
    /// Tracks this view as a screen while it is visible.
    ///
    /// - Parameter name: The screen name. Defaults to the name of the view type the modifier is
    ///   applied to.
    func otelScreen(_ name: String? = nil, tracker: ScreenTracker = .shared) -> some View {
      let resolvedName = name
        ?? ScreenNameResolver.screenName(fromTypeName: String(reflecting: Self.self))
        ?? String(describing: Self.self)
      return modifier(ScreenTrackingModifier(value: resolvedName,
                                             name: { $0 },
                                             source: .swiftUIScreen,
                                             tracker: tracker))
    }

    /// Tracks every screen of a `NavigationStack` from the path that drives it. Apply it to the
    /// `NavigationStack` itself.
    ///
    /// - Parameters:
    ///   - path: The same collection that is bound to the `NavigationStack`.
    ///   - rootName: The screen name to report while the path is empty.
    ///   - routeName: Maps the top route to a screen name. Defaults to the route's description
    ///     without associated values, so `Route.product(id: 42)` is reported as `product`.
    func otelTrackNavigation<Route: Hashable>(path: [Route],
                                              rootName: String,
                                              tracker: ScreenTracker = .shared,
                                              routeName: ((Route) -> String)? = nil) -> some View {
      let routeName = routeName ?? { ScreenNameResolver.routeName(for: $0) }
      return modifier(ScreenTrackingModifier(value: path,
                                             name: { $0.last.map(routeName) ?? rootName },
                                             source: .swiftUINavigation,
                                             tracker: tracker))
    }

    /// Tracks the selected tab of a `TabView` as a screen. Apply it to the `TabView` itself.
    ///
    /// - Parameters:
    ///   - selection: The same value that is bound to the `TabView`.
    ///   - tabName: Maps the selected tab to a screen name. Defaults to its description without
    ///     associated values.
    func otelTrackTabs<Selection: Hashable>(selection: Selection,
                                            tracker: ScreenTracker = .shared,
                                            tabName: ((Selection) -> String)? = nil) -> some View {
      modifier(ScreenTrackingModifier(value: selection,
                                      name: tabName ?? { ScreenNameResolver.routeName(for: $0) },
                                      source: .swiftUITabs,
                                      tracker: tracker))
    }
  }

  /// Reports the screen named after `value` while the modified view is visible, and again
  /// whenever `value` changes.
  struct ScreenTrackingModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let name: (Value) -> String
    let source: ScreenSource
    let tracker: ScreenTracker

    @State private var id = ScreenID()

    func body(content: Content) -> some View {
      content
        .onAppear { report(value) }
        .onDisappear { tracker.screenDisappeared(id: id) }
        .onChange(of: value) { newValue in report(newValue) }
    }

    private func report(_ value: Value) {
      tracker.screenAppeared(id: id, name: name(value), source: source)
    }
  }
#endif
