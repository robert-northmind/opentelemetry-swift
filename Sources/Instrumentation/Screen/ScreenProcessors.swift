/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Adds the current screen name to every span that does not already carry one when it starts.
public struct ScreenSpanProcessor: SpanProcessor {
  public let isStartRequired = true
  public let isEndRequired = false
  private let tracker: ScreenTracker

  public init(tracker: ScreenTracker = .shared) {
    self.tracker = tracker
  }

  public func onStart(parentContext: SpanContext?, span: ReadableSpan) {
    let key = SemanticConventions.App.screenName.rawValue
    guard span.getAttributes()[key] == nil, let name = tracker.currentScreenName else { return }
    span.setAttribute(key: key, value: name)
  }

  public func onEnd(span: ReadableSpan) {}

  public func shutdown(explicitTimeout: TimeInterval?) {}

  public func forceFlush(timeout: TimeInterval?) {}
}

/// Adds the current screen name to every log record that does not already carry one.
public struct ScreenLogRecordProcessor: LogRecordProcessor {
  private let nextProcessor: LogRecordProcessor
  private let tracker: ScreenTracker

  public init(nextProcessor: LogRecordProcessor, tracker: ScreenTracker = .shared) {
    self.nextProcessor = nextProcessor
    self.tracker = tracker
  }

  public func onEmit(logRecord: ReadableLogRecord) {
    let key = SemanticConventions.App.screenName.rawValue
    guard logRecord.attributes[key] == nil, let name = tracker.currentScreenName else {
      nextProcessor.onEmit(logRecord: logRecord)
      return
    }
    var enhancedRecord = logRecord
    enhancedRecord.setAttribute(key: key, value: .string(name))
    nextProcessor.onEmit(logRecord: enhancedRecord)
  }

  public func shutdown(explicitTimeout: TimeInterval?) -> ExportResult {
    nextProcessor.shutdown(explicitTimeout: explicitTimeout)
  }

  public func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
    nextProcessor.forceFlush(explicitTimeout: explicitTimeout)
  }
}
