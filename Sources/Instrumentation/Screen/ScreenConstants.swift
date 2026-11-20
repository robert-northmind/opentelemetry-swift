/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public enum ScreenConstants {
  /// Instrumentation scope of the loggers that emit screen events.
  static let instrumentationScopeName = "io.opentelemetry.screen"

  // The semantic conventions define `app.screen.name` (`SemanticConventions.App.screenName`) but
  // no navigation event and no previous-screen attribute yet
  // (open-telemetry/semantic-conventions#2474). The names below follow OpenTelemetry Android's
  // own conventions, so both SDKs report screen changes the same way, except `screenSource`.

  /// Name of the log event emitted when the current screen changes.
  /// OpenTelemetry Android convention.
  public static let navigationCompleteEvent = "app.navigation.complete"
  /// The screen that became current, on `navigationCompleteEvent`. Same value as
  /// `app.screen.name`. OpenTelemetry Android convention.
  public static let navigationDestinationName = "app.navigation.destination.name"
  /// The screen that was current before, on `navigationCompleteEvent`. Absent on the first
  /// event. OpenTelemetry Android convention.
  public static let previousScreenName = "app.screen.previous.name"
  /// The mechanism that reported the screen, a `ScreenSource` raw value, on
  /// `navigationCompleteEvent`. Specific to this instrumentation.
  public static let screenSource = "app.screen.source"
}
