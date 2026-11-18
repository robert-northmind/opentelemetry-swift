/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public struct ScreenInstrumentationConfiguration: Sendable {
  public static let defaultHostingSuppressionInterval: TimeInterval = 1

  /// The detection mechanisms to accept. Automatic detection of SwiftUI hosting controllers is
  /// experimental and therefore not part of the default.
  public var enabledSources: Set<ScreenSource>
  /// See `ScreenTracker.hostingSuppressionInterval`.
  public var hostingSuppressionInterval: TimeInterval
  /// Whether a hosting controller whose SwiftUI view type cannot be determined is named after
  /// its navigation title. Titles are user-facing text and may carry dynamic values.
  public var usesTitleForHostingControllers: Bool

  public init(enabledSources: Set<ScreenSource> = Set(ScreenSource.allCases).subtracting([.swiftUIHosting]),
              hostingSuppressionInterval: TimeInterval = ScreenInstrumentationConfiguration.defaultHostingSuppressionInterval,
              usesTitleForHostingControllers: Bool = true) {
    self.enabledSources = enabledSources
    self.hostingSuppressionInterval = hostingSuppressionInterval
    self.usesTitleForHostingControllers = usesTitleForHostingControllers
  }
}

/// Entry point for screen tracking.
///
/// Call `install()` once at startup, and add `ScreenSpanProcessor` and `ScreenLogRecordProcessor`
/// to the tracer and logger providers so every span and log record carries `app.screen.name`.
public enum ScreenInstrumentation {
  public static func install(configuration: ScreenInstrumentationConfiguration = .init()) {
    ScreenTracker.shared.hostingSuppressionInterval = configuration.hostingSuppressionInterval
    #if canImport(UIKit) && !os(watchOS)
      UIKitScreenTracking.setUsesTitleForHostingControllers(configuration.usesTitleForHostingControllers)
    #endif
    setEnabledSources(configuration.enabledSources)
  }

  /// Changes which detection mechanisms are accepted at runtime.
  public static func setEnabledSources(_ sources: Set<ScreenSource>) {
    ScreenTracker.shared.enabledSources = sources
    #if canImport(UIKit) && !os(watchOS)
      if sources.contains(.uiKit) || sources.contains(.swiftUIHosting) {
        UIKitScreenTracking.installIfNeeded()
      }
    #endif
  }
}
