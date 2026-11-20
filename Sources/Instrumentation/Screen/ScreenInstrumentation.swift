/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public struct ScreenInstrumentationConfiguration: Sendable {
  /// Whether UIKit view controllers are detected automatically (the `uiKit` source). On by
  /// default. Turn it off to name UIKit screens only through `ScreenTracker.setScreen(name:)`.
  ///
  /// UIKit and SwiftUI detection share the same hooks on `UIViewController.viewDidAppear(_:)`
  /// and `viewDidDisappear(_:)`. With both off, no method is swizzled. With only SwiftUI
  /// detection on, the hooks are installed but ignore view controllers that are not SwiftUI's.
  public var detectsUIKitScreensAutomatically: Bool

  /// Whether SwiftUI screens are detected automatically from the hosting controllers SwiftUI
  /// creates (the `swiftUIHosting` source). Off by default: the view type is read from SwiftUI
  /// internals through `Mirror`, which a SwiftUI release can change. Without it, SwiftUI screens
  /// are named through the SwiftUI modifiers and manual calls.
  public var detectsSwiftUIScreensAutomatically: Bool

  /// Whether a hosting controller whose SwiftUI view type cannot be determined is named after
  /// its navigation title. Off by default: titles are localized, so the same screen gets a
  /// different name in every language, and they may carry dynamic values or personal data
  /// ("Hi, Anna"). When on, it applies only to the root of a navigation stack, a tab or a
  /// presentation, never to pushed screens.
  public var usesTitleForHostingControllers: Bool

  public init(detectsUIKitScreensAutomatically: Bool = true,
              detectsSwiftUIScreensAutomatically: Bool = false,
              usesTitleForHostingControllers: Bool = false) {
    self.detectsUIKitScreensAutomatically = detectsUIKitScreensAutomatically
    self.detectsSwiftUIScreensAutomatically = detectsSwiftUIScreensAutomatically
    self.usesTitleForHostingControllers = usesTitleForHostingControllers
  }

  /// The sources whose reports are accepted. The SwiftUI modifiers and manual calls are always
  /// accepted: they only report when the app uses them.
  var enabledSources: Set<ScreenSource> {
    var sources = Set(ScreenSource.allCases)
    if !detectsUIKitScreensAutomatically {
      sources.remove(.uiKit)
    }
    if !detectsSwiftUIScreensAutomatically {
      sources.remove(.swiftUIHosting)
    }
    return sources
  }
}

/// Entry point for screen tracking.
///
/// Call `install()` once at startup, and add `ScreenSpanProcessor` and `ScreenLogRecordProcessor`
/// to the tracer and logger providers so every span and log record carries `app.screen.name`.
public enum ScreenInstrumentation {
  public static func install(configuration: ScreenInstrumentationConfiguration = .init()) {
    #if canImport(UIKit) && !os(watchOS)
      UIKitScreenTracking.setUsesTitleForHostingControllers(configuration.usesTitleForHostingControllers)
    #endif
    ScreenTracker.shared.updateEnabledSources { $0 = configuration.enabledSources }
    installAutomaticDetectionIfNeeded()
    #if canImport(UIKit) && !os(watchOS)
      UIKitScreenTracking.observeClosedScenesIfNeeded()
    #endif
  }

  /// Turns automatic detection of UIKit screens on or off at runtime. Turning it off removes
  /// UIKit screens from tracking; the hooks stay installed but ignore UIKit view controllers.
  /// See `ScreenInstrumentationConfiguration.detectsUIKitScreensAutomatically`.
  public static func setDetectsUIKitScreensAutomatically(_ enabled: Bool) {
    setSource(.uiKit, enabled: enabled)
  }

  /// Turns automatic detection of SwiftUI screens on or off at runtime. See
  /// `ScreenInstrumentationConfiguration.detectsSwiftUIScreensAutomatically`.
  public static func setDetectsSwiftUIScreensAutomatically(_ enabled: Bool) {
    setSource(.swiftUIHosting, enabled: enabled)
  }

  private static func setSource(_ source: ScreenSource, enabled: Bool) {
    ScreenTracker.shared.updateEnabledSources { sources in
      if enabled {
        sources.insert(source)
      } else {
        sources.remove(source)
      }
    }
    installAutomaticDetectionIfNeeded()
  }

  private static func installAutomaticDetectionIfNeeded() {
    #if canImport(UIKit) && !os(watchOS)
      let sources = ScreenTracker.shared.enabledSources
      if sources.contains(.uiKit) || sources.contains(.swiftUIHosting) {
        UIKitScreenTracking.installIfNeeded()
      }
    #endif
  }
}
