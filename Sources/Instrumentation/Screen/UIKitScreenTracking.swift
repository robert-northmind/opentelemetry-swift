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
    nonisolated(unsafe) private static var isInstalled = false
    nonisolated(unsafe) private static var usesTitleForHostingControllers = true
    nonisolated(unsafe) private static var appClassCache: [ObjectIdentifier: Bool] = [:]

    // Reflected type names of SwiftUI's own view controllers all start with this module prefix.
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
        MainActor.assumeIsolated { viewDidAppear(viewController) }
      }
      swizzle(#selector(UIViewController.viewDidDisappear(_:))) { viewController in
        ScreenTracker.shared.screenDisappeared(id: ScreenID(object: viewController))
      }
    }

    private static func swizzle(_ selector: Selector, onEvent: @escaping (UIViewController) -> Void) {
      guard let method = class_getInstanceMethod(UIViewController.self, selector) else { return }
      typealias Original = @convention(c) (UIViewController, Selector, Bool) -> Void
      let originalImplementation = method_getImplementation(method)
      let block: @convention(block) (UIViewController, Bool) -> Void = { viewController, animated in
        let original = unsafeBitCast(originalImplementation, to: Original.self)
        original(viewController, selector, animated)
        onEvent(viewController)
      }
      method_setImplementation(method, imp_implementationWithBlock(block))
    }

    @MainActor
    private static func viewDidAppear(_ viewController: UIViewController) {
      let viewControllerClass: AnyClass = type(of: viewController)
      let typeName = String(reflecting: viewControllerClass)
      let id = ScreenID(object: viewController)

      if typeName.hasPrefix(swiftUITypePrefix) {
        guard let name = hostingScreenName(for: viewController, typeName: typeName) else { return }
        ScreenTracker.shared.screenAppeared(id: id, name: name, source: .swiftUIHosting)
        return
      }

      guard isAppClass(viewControllerClass), !isContainer(viewController) else { return }
      let name: String?
      if let provider = viewController as? ScreenNameProviding {
        name = provider.screenName
      } else {
        name = String(describing: viewControllerClass)
      }
      guard let name else { return }
      ScreenTracker.shared.screenAppeared(id: id, name: name, source: .uiKit)
    }

    @MainActor
    private static func hostingScreenName(for viewController: UIViewController, typeName: String) -> String? {
      guard !isContainer(viewController) else { return nil }
      // A hosting controller embedded in one of the app's own view controllers is a piece of
      // that screen, not a screen of its own.
      if let parent = viewController.parent, isAppClass(type(of: parent)) {
        return nil
      }
      if let name = ScreenNameResolver.screenName(fromTypeName: typeName) {
        return name
      }
      guard lock.withLock({ usesTitleForHostingControllers }) else { return nil }
      if let title = viewController.navigationItem.title, !title.isEmpty {
        return title
      }
      if let title = viewController.title, !title.isEmpty {
        return title
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
