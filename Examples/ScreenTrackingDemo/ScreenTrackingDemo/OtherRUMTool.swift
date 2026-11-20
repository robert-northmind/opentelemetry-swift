/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import ObjectiveC
import UIKit

/// A stand-in for another RUM SDK that hooks the same `UIViewController` methods as screen
/// tracking, to check that both keep working side by side.
///
/// It hooks the methods the way some RUM SDKs do: the new implementation calls its
/// hook and then the implementation that was there before, and removing the hook puts that saved
/// implementation back with `method_setImplementation`.
@MainActor
enum OtherRUMTool {
  /// When the tool starts, relative to `ScreenInstrumentation.install`.
  enum InstallOrder: String, CaseIterable {
    case off
    case before
    case after
  }

  private static let orderKey = "otherRUMToolOrder"

  static var configuredOrder: InstallOrder {
    UserDefaults.standard.string(forKey: orderKey).flatMap(InstallOrder.init(rawValue:)) ?? .off
  }

  static func setConfiguredOrder(_ order: InstallOrder) {
    UserDefaults.standard.set(order.rawValue, forKey: orderKey)
  }

  private struct Hook {
    let method: Method
    let previous: IMP
  }

  private static var hooks: [Hook] = []
  private(set) static var appearCount = 0
  static var isRunning: Bool { !hooks.isEmpty }

  static func start() {
    guard !isRunning else { return }
    hook(#selector(UIViewController.viewDidAppear(_:)), event: "viewDidAppear")
    hook(#selector(UIViewController.viewDidDisappear(_:)), event: "viewDidDisappear")
    NSLog("[otel] [other-rum] started")
  }

  /// Puts back the implementations saved by `start()`.
  static func stop() {
    guard isRunning else { return }
    for hook in hooks.reversed() {
      method_setImplementation(hook.method, hook.previous)
    }
    hooks.removeAll()
    NSLog("[otel] [other-rum] stopped")
  }

  private static func hook(_ selector: Selector, event: String) {
    guard let method = class_getInstanceMethod(UIViewController.self, selector) else { return }
    typealias Original = @convention(c) (UIViewController, Selector, Bool) -> Void
    let previous = method_getImplementation(method)
    let block: @convention(block) (UIViewController, Bool) -> Void = { viewController, animated in
      // Like those SDKs, the hook runs before the previous implementation.
      if Thread.isMainThread, event == "viewDidAppear" {
        MainActor.assumeIsolated { appearCount += 1 }
      }
      NSLog("[otel] [other-rum] %@ %@", event, String(describing: type(of: viewController)))
      unsafeBitCast(previous, to: Original.self)(viewController, selector, animated)
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
    hooks.append(Hook(method: method, previous: previous))
  }
}
