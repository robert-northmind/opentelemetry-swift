/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public enum ScreenConstants {
  static let instrumentationScopeName = "io.opentelemetry.screen"

  // The semantic conventions define `app.screen.name` but no screen-view event and no
  // previous-screen attribute yet (open-telemetry/semantic-conventions#2474), so these are local.
  public static let screenViewEvent = "app.screen.view"
  public static let previousScreenName = "app.screen.previous.name"
  public static let screenSource = "app.screen.source"
}
