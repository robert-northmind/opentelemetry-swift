/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if canImport(UIKit) && !os(watchOS)
  import Foundation
  import ObjectiveC
  import UIKit

  /// Lets a view controller choose the name it is tracked under instead of its class name.
  /// Return `nil` to exclude the view controller from tracking.
  @MainActor
  public protocol ScreenNameProviding {
    var screenName: String? { get }
  }

  /// Automatic screen detection through `UIViewController.viewDidAppear` and `viewDidDisappear`.
  enum UIKitScreenTracking {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var isInstalled = false
    private nonisolated(unsafe) static var usesTitleForHostingControllers = false
    private nonisolated(unsafe) static var appClassCache: [ObjectIdentifier: Bool] = [:]
    /// View controllers that an explicit SwiftUI modifier names, with what the modifier covers.
    /// Automatic detection leaves them alone for as long as they live.
    @MainActor private static let claims = NSMapTable<UIViewController, ClaimBox>.weakToStrongObjects()

    private final class ClaimBox {
      let claim: HostingClaim
      init(_ claim: HostingClaim) {
        self.claim = claim
      }
    }

    /// Reflected type names of SwiftUI's own view controllers all start with this module prefix.
    private static let swiftUITypePrefix = "SwiftUI."

    static func setUsesTitleForHostingControllers(_ value: Bool) {
      lock.withLock { usesTitleForHostingControllers = value }
    }

    static func installIfNeeded() {
      let shouldInstall: Bool = lock.withLock {
        guard !isInstalled else { return false }
        isInstalled = true
        return true
      }
      guard shouldInstall else { return }
      swizzle(#selector(UIViewController.viewDidAppear(_:))) { viewController in
        viewDidAppear(viewController)
      }
      swizzle(#selector(UIViewController.viewDidDisappear(_:))) { viewController in
        ScreenTracker.shared.screenDisappeared(id: ScreenID(object: viewController),
                                               isCovered: !isClosing(viewController))
      }
    }

    private nonisolated(unsafe) static var isObservingScenes = false

    /// Screens in a window that is closed get no disappearance callbacks, so the tracker checks
    /// again which screens still exist once a scene is gone.
    static func observeClosedScenesIfNeeded() {
      let shouldObserve: Bool = lock.withLock {
        guard !isObservingScenes else { return false }
        isObservingScenes = true
        return true
      }
      guard shouldObserve else { return }
      NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification,
                                             object: nil,
                                             queue: .main) { _ in
        ScreenTracker.shared.revalidate()
      }
    }

    /// Calls `onEvent` after the original implementation, on the main thread only. Appearance
    /// methods called from another thread are an app bug; they are passed on but not tracked.
    private static func swizzle(_ selector: Selector, onEvent: @escaping @MainActor (UIViewController) -> Void) {
      guard let method = class_getInstanceMethod(UIViewController.self, selector) else { return }
      typealias Original = @convention(c) (UIViewController, Selector, Bool) -> Void
      let originalImplementation = method_getImplementation(method)
      let block: @convention(block) (UIViewController, Bool) -> Void = { viewController, animated in
        let original = unsafeBitCast(originalImplementation, to: Original.self)
        original(viewController, selector, animated)
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { onEvent(viewController) }
      }
      method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// Records that an explicit modifier names `viewController` (and, depending on `claim`,
    /// screens inside it). Called before the controller appears; if it was reported already,
    /// that report is withdrawn.
    @MainActor
    static func claim(_ viewController: UIViewController, as claim: HostingClaim, tracker: ScreenTracker) {
      if let existing = claims.object(forKey: viewController), existing.claim == claim {
        return
      }
      // A view controller can hold a screen and a navigation stack at once; the stack claim
      // covers more of it.
      if claims.object(forKey: viewController)?.claim != .navigationStacks {
        claims.setObject(ClaimBox(claim), forKey: viewController)
      }
      tracker.screenDisappeared(id: ScreenID(object: viewController))
    }

    /// Whether an explicit modifier names this view controller's screen.
    @MainActor
    private static func isClaimed(_ viewController: UIViewController) -> Bool {
      func claim(of viewController: UIViewController) -> HostingClaim? {
        claims.object(forKey: viewController)?.claim
      }
      if claim(of: viewController) != nil {
        return true
      }
      var child = viewController
      var isInNavigationStack = false
      var isPushed = false
      while let parent = child.parent {
        // A tab or a column is a different screen from what contains it.
        if parent is UITabBarController || parent is UISplitViewController || parent is UIPageViewController {
          return false
        }
        if let navigationController = parent as? UINavigationController {
          isInNavigationStack = true
          if navigationController.viewControllers.first !== child {
            isPushed = true
          }
        }
        switch claim(of: parent) {
        case .screen: return !isPushed
        case .navigationStacks: return isInNavigationStack
        case nil: break
        }
        child = parent
      }
      return false
    }

    @MainActor
    private static func viewDidAppear(_ viewController: UIViewController) {
      let viewControllerClass: AnyClass = type(of: viewController)
      let typeName = String(reflecting: viewControllerClass)
      let isHostingController = typeName.hasPrefix(swiftUITypePrefix)
      // The hooks serve both UIKit and SwiftUI detection; skip the work for the one that is off.
      guard ScreenTracker.shared.enabledSources.contains(isHostingController ? .swiftUIHosting : .uiKit) else {
        return
      }
      let id = ScreenID(object: viewController)
      guard !isClaimed(viewController), !isInOverlayWindow(viewController) else { return }
      let isAlive: ScreenTracker.Liveness = { [weak viewController] in
        guard let viewController else { return false }
        guard Thread.isMainThread else { return true }
        return MainActor.assumeIsolated { !isDetached(viewController) }
      }

      // Filters decide whether the view controller is a screen at all; naming then decides what
      // it is called. A screen without a name is not tracked.
      let name: String?
      if isHostingController {
        guard isHostingScreen(viewController) else { return }
        name = hostingScreenName(for: viewController, typeName: typeName)
      } else {
        guard isUIKitScreen(viewController) else { return }
        name = uiKitScreenName(for: viewController)
      }
      guard let name else {
        // It may have been reported under a name on an earlier appearance.
        ScreenTracker.shared.screenDisappeared(id: id)
        return
      }
      // The hosting controller at the root of the window holds the whole app, including any tab
      // bar or navigation stack, so it only stands in while nothing more specific is known.
      let isRoot = isHostingController
        && viewController.parent == nil && viewController.presentingViewController == nil
      ScreenTracker.shared.report(id: id,
                                  name: name,
                                  source: isHostingController ? .swiftUIHosting : .uiKit,
                                  isReappearing: isRoot,
                                  isContainer: isRoot,
                                  isAlive: isAlive)
    }

    /// Whether an app view controller is a screen of its own.
    @MainActor
    private static func isUIKitScreen(_ viewController: UIViewController) -> Bool {
      guard isAppClass(type(of: viewController)), !isContainer(viewController) else { return false }
      // A child of one of the app's own view controllers (a pane, a mini player, a banner) is a
      // part of that screen. Children of system containers are screens.
      if let parent = viewController.parent, !isContainer(parent), isAppClass(type(of: parent)) {
        return false
      }
      return true
    }

    @MainActor
    private static func uiKitScreenName(for viewController: UIViewController) -> String? {
      if let provider = viewController as? ScreenNameProviding {
        return provider.screenName
      }
      return String(describing: type(of: viewController))
    }

    /// Whether the view controller is going away for good (popped, dismissed, removed from its
    /// parent, or taken out of its window), as opposed to being covered by another view
    /// controller.
    @MainActor
    private static func isClosing(_ viewController: UIViewController) -> Bool {
      var candidate: UIViewController? = viewController
      while let current = candidate {
        if current.isMovingFromParent || current.isBeingDismissed {
          return true
        }
        candidate = current.parent
      }
      return isDetached(viewController)
    }

    /// Whether the view controller is no longer part of any window's hierarchy: its topmost
    /// ancestor is neither in a window nor presenting or presented. Covered view controllers
    /// stay attached through their navigation controller, tab bar controller or presentation.
    @MainActor
    private static func isDetached(_ viewController: UIViewController) -> Bool {
      var topmost = viewController
      while let parent = topmost.parent {
        topmost = parent
      }
      return topmost.viewIfLoaded?.window == nil
        && topmost.presentingViewController == nil
        && topmost.presentedViewController == nil
    }

    /// Toasts, banners and HUDs are often shown in a window of their own above the app.
    @MainActor
    private static func isInOverlayWindow(_ viewController: UIViewController) -> Bool {
      guard let window = viewController.viewIfLoaded?.window else { return false }
      return window.windowLevel > .normal
    }

    /// Whether a SwiftUI hosting controller is a screen of its own.
    @MainActor
    private static func isHostingScreen(_ viewController: UIViewController) -> Bool {
      // SwiftUI presents alerts and confirmation dialogs in a UIAlertController subclass.
      guard !isContainer(viewController), !(viewController is UIAlertController) else { return false }
      // A hosting controller embedded in one of the app's own view controllers is a piece of
      // that screen, not a screen of its own.
      if let parent = viewController.parent, isAppClass(type(of: parent)) {
        return false
      }
      // A hosting controller around a NavigationStack or TabView: the screens are the
      // controllers inside it.
      return !viewController.children.contains(where: { isContainer($0) })
    }

    @MainActor
    private static func hostingScreenName(for viewController: UIViewController,
                                          typeName: String) -> String? {
      // A hosting controller typed with the app's view names it without reading SwiftUI's
      // internals. Type-erased hosts (navigation destinations, sheets) need the hosted view.
      if let name = ScreenNameResolver.viewName(fromTypeName: typeName) {
        return name
      }
      if let name = hostedViewName(of: viewController) {
        return name
      }
      if let name = enclosingViewName(ofStackRoot: viewController) {
        return name
      }
      guard lock.withLock({ usesTitleForHostingControllers }) else { return nil }
      // Titles of pushed screens often carry data ("Order 1234"), which would make every
      // instance a screen of its own. The root of a navigation stack, a tab or a sheet usually
      // has a fixed title.
      if let navigationController = viewController.navigationController,
         navigationController.viewControllers.first !== viewController {
        return nil
      }
      if let title = viewController.navigationItem.title, !title.isEmpty {
        return title
      }
      if let title = viewController.title, !title.isEmpty {
        return title
      }
      return nil
    }

    /// For the root of a navigation stack, the app view the stack is part of, as in
    /// `.sheet { SettingsView() }` where `SettingsView` wraps its content in a `NavigationStack`,
    /// or a column of a `NavigationSplitView` inside `MailView`. The root's own content is usually
    /// a `List` or `Form` with no name of its own.
    @MainActor
    private static func enclosingViewName(ofStackRoot viewController: UIViewController) -> String? {
      guard let navigationController = viewController.navigationController,
            navigationController.viewControllers.first === viewController,
            var enclosing = navigationController.parent else {
        return nil
      }
      // The columns of a NavigationSplitView are stacks inside a split view controller. When a
      // modifier names one of the columns, the others are not named after the whole view.
      if let splitViewController = enclosing as? UISplitViewController, let parent = enclosing.parent {
        if splitViewController.children.contains(where: isColumnClaimed) {
          return nil
        }
        enclosing = parent
      }
      guard String(reflecting: type(of: enclosing)).hasPrefix(swiftUITypePrefix),
            !isContainer(enclosing) else {
        return nil
      }
      return hostedViewName(of: enclosing)
    }

    /// Whether a modifier names the screen at the root of a split view column.
    @MainActor
    private static func isColumnClaimed(_ column: UIViewController) -> Bool {
      let root = (column as? UINavigationController)?.viewControllers.first ?? column
      return claims.object(forKey: root) != nil || claims.object(forKey: column) != nil
    }

    /// The name of the SwiftUI view a hosting controller shows. SwiftUI hosts navigation
    /// destinations, sheets and other presented content as `AnyView`, which hides the view's type
    /// in the controller's own type name; the `AnyView`'s storage still carries it.
    ///
    /// This reads SwiftUI's stored properties through `Mirror`, following only wrappers
    /// (`AnyView`, modifiers, optionals) and never the content of system views. The property names
    /// are not public API and may change, in which case this returns `nil` and the caller falls back to
    /// other information.
    @MainActor
    private static func hostedViewName(of viewController: UIViewController) -> String? {
      guard let host = mirrorChild(named: "host", of: viewController),
            var value = mirrorChild(named: "_rootView", of: host) else {
        return nil
      }
      for _ in 0 ..< 32 {
        let typeName = String(reflecting: type(of: value))
        if let name = ScreenNameResolver.viewName(fromTypeName: typeName) {
          return name
        }
        guard ScreenNameResolver.isHostedViewWrapper(typeName),
              let wrapped = wrappedLabels.lazy.compactMap({ mirrorChild(named: $0, of: value) }).first else {
          return nil
        }
        value = wrapped
      }
      return nil
    }

    /// Where the wrapped view is stored in `AnyView`, its storage, `ModifiedContent`, and
    /// `Optional`.
    private static let wrappedLabels = ["storage", "view", "content", "some"]

    private static func mirrorChild(named label: String, of value: Any) -> Any? {
      var mirror: Mirror? = Mirror(reflecting: value)
      while let current = mirror {
        if let child = current.children.first(where: { $0.label == label }) {
          return child.value
        }
        mirror = current.superclassMirror
      }
      return nil
    }

    @MainActor
    private static func isContainer(_ viewController: UIViewController) -> Bool {
      viewController is UINavigationController
        || viewController is UITabBarController
        || viewController is UISplitViewController
        || viewController is UIPageViewController
    }

    /// Whether the class is defined in the app or one of its embedded frameworks, as opposed to
    /// a system framework.
    private static func isAppClass(_ viewControllerClass: AnyClass) -> Bool {
      let key = ObjectIdentifier(viewControllerClass)
      if let cached = lock.withLock({ appClassCache[key] }) {
        return cached
      }
      let isAppClass = Bundle(for: viewControllerClass).bundlePath.hasPrefix(Bundle.main.bundlePath)
      lock.withLock { appClassCache[key] = isAppClass }
      return isAppClass
    }
  }
#endif
