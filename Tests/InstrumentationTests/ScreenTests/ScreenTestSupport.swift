/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
@testable import ScreenInstrumentation

final class CollectingLogRecordExporter: LogRecordExporter, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [ReadableLogRecord] = []

  var records: [ReadableLogRecord] {
    lock.withLock { storage }
  }

  func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
    lock.withLock { storage.append(contentsOf: logRecords) }
    return .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {}

  func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
    .success
  }
}

/// Runs scheduled work only when asked, standing in for the main queue.
final class ManualScheduler: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [@Sendable () -> Void] = []

  func schedule(_ work: @escaping @Sendable () -> Void) {
    lock.withLock { pending.append(work) }
  }

  func runPending() {
    let work: [@Sendable () -> Void] = lock.withLock {
      let snapshot = pending
      pending.removeAll()
      return snapshot
    }
    work.forEach { $0() }
  }
}

final class ManualClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current = Date(timeIntervalSince1970: 1_000_000)

  var now: Date {
    lock.withLock { current }
  }

  func advance(by interval: TimeInterval) {
    lock.withLock { current = current.addingTimeInterval(interval) }
  }
}

struct TrackerFixture {
  let exporter = CollectingLogRecordExporter()
  let scheduler = ManualScheduler()
  let clock = ManualClock()
  let tracker: ScreenTracker

  init() {
    let provider = LoggerProviderBuilder()
      .with(processors: [SimpleLogRecordProcessor(logRecordExporter: exporter)])
      .build()
    let scheduler = scheduler
    let clock = clock
    tracker = ScreenTracker(loggerProvider: provider,
                            clock: { clock.now },
                            scheduler: { scheduler.schedule($0) })
  }

  /// Runs the deferred work the tracker scheduled, as the next turn of the main queue would.
  func settle() {
    scheduler.runPending()
  }

  /// The `(previous, current, source)` of every screen-view event emitted so far.
  var transitions: [Transition] {
    exporter.records
      .filter { $0.eventName == ScreenConstants.navigationCompleteEvent }
      .map {
        Transition(from: $0.attributes[ScreenConstants.previousScreenName]?.description,
                   to: $0.attributes[SemanticConventions.App.screenName.rawValue]?.description,
                   source: $0.attributes[ScreenConstants.screenSource]?.description)
      }
  }
}

struct Transition: Equatable {
  let from: String?
  let to: String?
  let source: String?

  init(from: String?, to: String?, source: String?) {
    self.from = from
    self.to = to
    self.source = source
  }

  init(_ from: String?, _ to: String, _ source: ScreenSource) {
    self.init(from: from, to: to, source: source.rawValue)
  }
}
