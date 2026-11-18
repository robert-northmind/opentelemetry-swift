/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import XCTest
import OpenTelemetryApi
import OpenTelemetrySdk
@testable import ScreenInstrumentation

final class ScreenProcessorsTests: XCTestCase {
  private let screenNameKey = SemanticConventions.App.screenName.rawValue

  func testSpanStartedOnScreenCarriesScreenName() {
    let fixture = TrackerFixture()
    let tracerProvider = TracerProviderBuilder()
      .add(spanProcessor: ScreenSpanProcessor(tracker: fixture.tracker))
      .build()
    let tracer = tracerProvider.get(instrumentationName: "test")
    fixture.tracker.setScreen(name: "Checkout")

    let span = tracer.spanBuilder(spanName: "pay").startSpan()
    fixture.tracker.setScreen(name: "Confirmation")
    span.end()

    let attributes = (span as? ReadableSpan)?.toSpanData().attributes
    XCTAssertEqual(attributes?[screenNameKey], .string("Checkout"), "the screen at span start is kept")
  }

  func testSpanStartedBeforeAnyScreenHasNoScreenName() {
    let fixture = TrackerFixture()
    let tracerProvider = TracerProviderBuilder()
      .add(spanProcessor: ScreenSpanProcessor(tracker: fixture.tracker))
      .build()

    let span = tracerProvider.get(instrumentationName: "test").spanBuilder(spanName: "launch").startSpan()
    span.end()

    let attributes = (span as? ReadableSpan)?.toSpanData().attributes
    XCTAssertNotNil(attributes)
    XCTAssertNil(attributes?[screenNameKey])
  }

  func testLogRecordCarriesCurrentScreenName() {
    let fixture = TrackerFixture()
    let exporter = CollectingLogRecordExporter()
    let logger = makeLogger(exporter: exporter, tracker: fixture.tracker)
    fixture.tracker.setScreen(name: "Checkout")

    logger.logRecordBuilder().setBody(.string("tapped pay")).emit()

    XCTAssertEqual(exporter.records.count, 1)
    XCTAssertEqual(exporter.records.first?.attributes[screenNameKey], .string("Checkout"))
  }

  func testLogRecordWithOwnScreenNameIsLeftUntouched() {
    let fixture = TrackerFixture()
    let exporter = CollectingLogRecordExporter()
    let logger = makeLogger(exporter: exporter, tracker: fixture.tracker)
    fixture.tracker.setScreen(name: "Checkout")

    logger.logRecordBuilder().setAttributes([screenNameKey: .string("Cart")]).emit()

    XCTAssertEqual(exporter.records.first?.attributes[screenNameKey], .string("Cart"))
  }

  func testLogRecordBeforeAnyScreenIsForwardedUnchanged() {
    let fixture = TrackerFixture()
    let exporter = CollectingLogRecordExporter()
    let logger = makeLogger(exporter: exporter, tracker: fixture.tracker)

    logger.logRecordBuilder().setBody(.string("launch")).emit()

    XCTAssertEqual(exporter.records.count, 1)
    XCTAssertNil(exporter.records.first?.attributes[screenNameKey])
  }

  func testScreenViewEventKeepsItsOwnNameThroughProcessor() {
    let exporter = CollectingLogRecordExporter()
    let scheduler = ManualScheduler()
    // The tracker emits through a provider whose processor reads the same tracker, as in an app.
    final class TrackerBox: @unchecked Sendable { var tracker: ScreenTracker? }
    let box = TrackerBox()
    let provider = LoggerProviderBuilder()
      .with(processors: [LazyScreenProcessor(box: { box.tracker }, exporter: exporter)])
      .build()
    let tracker = ScreenTracker(loggerProvider: provider, scheduler: { scheduler.schedule($0) })
    box.tracker = tracker

    tracker.setScreen(name: "Home")
    scheduler.runPending()
    tracker.setScreen(name: "Detail")
    scheduler.runPending()

    let names = exporter.records.map { $0.attributes[screenNameKey] }
    XCTAssertEqual(names, [.string("Home"), .string("Detail")])
    XCTAssertEqual(exporter.records.last?.attributes[ScreenConstants.previousScreenName], .string("Home"))
  }

  private func makeLogger(exporter: CollectingLogRecordExporter, tracker: ScreenTracker) -> Logger {
    let processor = ScreenLogRecordProcessor(
      nextProcessor: SimpleLogRecordProcessor(logRecordExporter: exporter),
      tracker: tracker
    )
    return LoggerProviderBuilder()
      .with(processors: [processor])
      .build()
      .get(instrumentationScopeName: "test")
  }
}

/// Builds the screen processor on first use so a tracker can emit through its own processor.
private struct LazyScreenProcessor: LogRecordProcessor {
  let box: @Sendable () -> ScreenTracker?
  let exporter: CollectingLogRecordExporter

  func onEmit(logRecord: ReadableLogRecord) {
    guard let tracker = box() else { return }
    ScreenLogRecordProcessor(nextProcessor: SimpleLogRecordProcessor(logRecordExporter: exporter),
                             tracker: tracker)
      .onEmit(logRecord: logRecord)
  }

  func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult { .success }

  func shutdown(explicitTimeout: TimeInterval?) -> ExportResult { .success }
}
