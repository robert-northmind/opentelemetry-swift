/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if canImport(SwiftUI)
  import SwiftUI
  #if canImport(UIKit) && !os(watchOS)
    import UIKit
  #endif

  public extension View {
    /// Tracks this view as a screen while it is visible.
    ///
    /// Apply it to the screen's outermost view, not to a view inside a `List` or another lazy
    /// container: those appear and disappear as the user scrolls.
    ///
    /// The screen's hosting controller is then left to this modifier: automatic detection does
    /// not report it under a second name.
    ///
    /// - Parameter name: The screen name. Defaults to the name of the view type the modifier is
    ///   applied to, as in `ProfileView().otelScreen()`. Inside a `body`, the modifier is applied
    ///   to whatever the body is built from; when that is a system view such as `List`, the name
    ///   of the source file is used instead, so prefer an explicit name there.
    func otelScreen(_ name: String? = nil, fileID: String = #fileID) -> some View {
      otelScreen(name, tracker: .shared, fileID: fileID)
    }

    /// Tracks every screen of a `NavigationStack` from the path that drives it. Apply it to the
    /// `NavigationStack` itself.
    ///
    /// The stack's screens are then left to this modifier: automatic detection does not report
    /// them under a second name.
    ///
    /// - Parameters:
    ///   - path: The same collection that is bound to the `NavigationStack`.
    ///   - rootName: The screen name to report while the path is empty.
    ///   - routeName: Maps the top route to a screen name. Defaults to the enum case without
    ///     associated values, so `Route.product(id: 42)` is reported as `product`. Routes that
    ///     are not enums are reported under their type name, never their value, so pass a
    ///     mapping for `String` or `Int` paths.
    func otelTrackNavigation<Route: Hashable>(path: [Route],
                                              rootName: String,
                                              routeName: ((Route) -> String)? = nil) -> some View {
      otelTrackNavigation(path: path, rootName: rootName, tracker: .shared, routeName: routeName)
    }

    /// Tracks the selected tab of a `TabView` as a screen. Apply it to the `TabView` itself.
    ///
    /// - Parameters:
    ///   - selection: The same value that is bound to the `TabView`.
    ///   - tabName: Maps the selected tab to a screen name. Defaults to the enum case without
    ///     associated values. Selections that are not enums are reported under their type name,
    ///     so pass a mapping for `Int` or `String` selections.
    func otelTrackTabs<Selection: Hashable>(selection: Selection,
                                            tabName: ((Selection) -> String)? = nil) -> some View {
      otelTrackTabs(selection: selection, tracker: .shared, tabName: tabName)
    }
  }

  extension View {
    func otelScreen(_ name: String?, tracker: ScreenTracker, fileID: String) -> some View {
      let resolvedName = name
        ?? ScreenNameResolver.viewName(fromTypeName: String(reflecting: Self.self))
        ?? ScreenNameResolver.fileName(fromFileID: fileID)
      return modifier(ScreenTrackingModifier(value: resolvedName,
                                             name: { $0 },
                                             source: .swiftUIScreen,
                                             claim: .screen,
                                             tracker: tracker))
    }

    func otelTrackNavigation<Route: Hashable>(path: [Route],
                                              rootName: String,
                                              tracker: ScreenTracker,
                                              routeName: ((Route) -> String)?) -> some View {
      let routeName = routeName ?? { ScreenNameResolver.routeName(for: $0) }
      return modifier(ScreenTrackingModifier(value: path,
                                             name: { $0.last.map(routeName) ?? rootName },
                                             source: .swiftUINavigation,
                                             claim: .navigationStacks,
                                             tracker: tracker))
    }

    func otelTrackTabs<Selection: Hashable>(selection: Selection,
                                            tracker: ScreenTracker,
                                            tabName: ((Selection) -> String)?) -> some View {
      modifier(ScreenTrackingModifier(value: selection,
                                      name: tabName ?? { ScreenNameResolver.routeName(for: $0) },
                                      source: .swiftUITabs,
                                      isContainer: true,
                                      tracker: tracker))
    }
  }

  /// Reports the screen named after `value` while the modified view is visible, and again
  /// whenever `value` changes.
  struct ScreenTrackingModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let name: (Value) -> String
    let source: ScreenSource
    var isContainer = false
    /// Which hosting controllers the modifier names, so that automatic detection leaves them
    /// alone.
    var claim: HostingClaim?
    let tracker: ScreenTracker

    @State private var id = ScreenID()
    @State private var hasAppeared = false
    #if canImport(UIKit) && !os(watchOS)
      @State private var anchor = SceneAnchor()
    #endif

    func body(content: Content) -> some View {
      claiming(content)
        .onAppear {
          // Appearing again means returning to this view: the back navigation or the dismissal
          // that reveals it has only started and may still be cancelled.
          report(value, isReappearing: hasAppeared)
          hasAppeared = true
        }
        .onDisappear { tracker.screenDisappeared(id: id) }
      #if os(visionOS)
        .onChange(of: value) { _, newValue in report(newValue, isReappearing: false) }
      #else
        .onChange(of: value) { newValue in report(newValue, isReappearing: false) }
      #endif
    }

    @ViewBuilder
    private func claiming(_ content: Content) -> some View {
      #if canImport(UIKit) && !os(watchOS)
        content.background(AnchorView(claim: claim, anchor: anchor, tracker: tracker))
      #else
        content
      #endif
    }

    private func report(_ value: Value, isReappearing: Bool) {
      #if canImport(UIKit) && !os(watchOS)
        let isAlive: ScreenTracker.Liveness? = { [anchor] in anchor.isAlive }
      #else
        let isAlive: ScreenTracker.Liveness? = nil
      #endif
      tracker.report(id: id,
                     name: name(value),
                     source: source,
                     isReappearing: isReappearing,
                     isContainer: isContainer,
                     isAlive: isAlive)
    }
  }

  /// The hosting controllers an explicit modifier names.
  enum HostingClaim {
    /// The hosting controller the modified view is in, and the root of a navigation stack
    /// directly inside it.
    case screen
    /// Every screen of the navigation stacks inside the hosting controller the modified view is
    /// in.
    case navigationStacks
  }

  #if canImport(UIKit) && !os(watchOS)
    /// The window scene a modifier's view is shown in. A screen in a window that was closed no
    /// longer exists, even though SwiftUI does not call `onDisappear` for it.
    final class SceneAnchor: @unchecked Sendable {
      /// Only accessed on the main thread.
      private weak var scene: UIWindowScene?
      private var hasScene = false

      @MainActor
      func update(_ scene: UIWindowScene?) {
        guard let scene else { return }
        self.scene = scene
        hasScene = true
      }

      var isAlive: Bool {
        guard Thread.isMainThread else { return true }
        return MainActor.assumeIsolated {
          guard hasScene else { return true }
          guard let scene else { return false }
          return scene.activationState != .unattached
        }
      }
    }

    /// An invisible view placed behind the modified view. Once it is in a window, it records the
    /// window's scene and, for modifiers that name their hosting controller, claims that
    /// controller before its `viewDidAppear`.
    private struct AnchorView: UIViewRepresentable {
      let claim: HostingClaim?
      let anchor: SceneAnchor
      let tracker: ScreenTracker

      func makeUIView(context: Context) -> AnchoringView {
        AnchoringView(claim: claim, anchor: anchor, tracker: tracker)
      }

      func updateUIView(_ view: AnchoringView, context: Context) {}
    }

    private final class AnchoringView: UIView {
      private let claim: HostingClaim?
      private let anchor: SceneAnchor
      private let tracker: ScreenTracker

      init(claim: HostingClaim?, anchor: SceneAnchor, tracker: ScreenTracker) {
        self.claim = claim
        self.anchor = anchor
        self.tracker = tracker
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
      }

      @available(*, unavailable)
      required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
      }

      override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else { return }
        anchor.update(window.windowScene)
        if let claim, let viewController = owningViewController {
          UIKitScreenTracking.claim(viewController, as: claim, tracker: tracker)
        }
      }

      private var owningViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
          if let viewController = current as? UIViewController {
            return viewController
          }
          responder = current.next
        }
        return nil
      }
    }
  #endif
#endif
