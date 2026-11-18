/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import ScreenInstrumentation

/// One line in the on-screen telemetry log.
struct DemoEvent: Identifiable, Sendable {
  enum Kind: Sendable {
    case screenView
    case log
    case span
  }

  let id = UUID()
  let time = Date()
  let kind: Kind
  let title: String
  let detail: String
}

/// Wires the OpenTelemetry SDK so that everything it produces ends up in the on-screen log.
enum Telemetry {
  private static let demoScopeName = "ScreenTrackingDemo"

  static func setUp(sink: @escaping @Sendable (DemoEvent) -> Void) {
    let logProcessor = ScreenLogRecordProcessor(
      nextProcessor: SimpleLogRecordProcessor(logRecordExporter: DemoLogExporter(sink: sink))
    )
    OpenTelemetry.registerLoggerProvider(
      loggerProvider: LoggerProviderBuilder().with(processors: [logProcessor]).build()
    )
    OpenTelemetry.registerTracerProvider(
      tracerProvider: TracerProviderBuilder()
        .add(spanProcessor: ScreenSpanProcessor())
        .add(spanProcessor: SimpleSpanProcessor(spanExporter: DemoSpanExporter(sink: sink)))
        .build()
    )
    ScreenInstrumentation.install(
      configuration: ScreenInstrumentationConfiguration(enabledSources: SourceSettings.load())
    )
  }

  /// Emits an ordinary span and log record, to show that both carry the current screen name.
  static func emitSampleSpanAndLog() {
    let span = OpenTelemetry.instance.tracerProvider
      .get(instrumentationName: demoScopeName)
      .spanBuilder(spanName: "demo.button_tap")
      .startSpan()
    span.end()
    OpenTelemetry.instance.loggerProvider
      .get(instrumentationScopeName: demoScopeName)
      .logRecordBuilder()
      .setBody(.string("demo log record"))
      .emit()
  }
}

/// Persists which detection mechanisms are switched on between launches.
enum SourceSettings {
  private static let defaultsKey = "enabledScreenSources"

  static func load() -> Set<ScreenSource> {
    guard let rawValues = UserDefaults.standard.stringArray(forKey: defaultsKey) else {
      return ScreenInstrumentationConfiguration().enabledSources
    }
    return Set(rawValues.compactMap(ScreenSource.init(rawValue:)))
  }

  static func save(_ sources: Set<ScreenSource>) {
    UserDefaults.standard.set(sources.map(\.rawValue), forKey: defaultsKey)
  }
}

private let screenNameKey = SemanticConventions.App.screenName.rawValue

private func screenDescription(_ attributes: [String: AttributeValue]) -> String {
  "\(screenNameKey) = \(attributes[screenNameKey]?.description ?? "<none>")"
}

final class DemoLogExporter: LogRecordExporter, @unchecked Sendable {
  private let sink: @Sendable (DemoEvent) -> Void

  init(sink: @escaping @Sendable (DemoEvent) -> Void) {
    self.sink = sink
  }

  func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
    for record in logRecords {
      let event: DemoEvent
      if record.eventName == ScreenConstants.screenViewEvent {
        let previous = record.attributes[ScreenConstants.previousScreenName]?.description ?? "<none>"
        let current = record.attributes[screenNameKey]?.description ?? "<none>"
        let source = record.attributes[ScreenConstants.screenSource]?.description ?? "<none>"
        event = DemoEvent(kind: .screenView, title: "\(previous) → \(current)", detail: "source: \(source)")
      } else {
        event = DemoEvent(kind: .log,
                          title: "log: \(record.body?.description ?? record.eventName ?? "<empty>")",
                          detail: screenDescription(record.attributes))
      }
      print("[otel] \(event.title) | \(event.detail)")
      sink(event)
    }
    return .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {}

  func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
    .success
  }
}

final class DemoSpanExporter: SpanExporter, @unchecked Sendable {
  private let sink: @Sendable (DemoEvent) -> Void

  init(sink: @escaping @Sendable (DemoEvent) -> Void) {
    self.sink = sink
  }

  func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    for span in spans {
      let event = DemoEvent(kind: .span, title: "span: \(span.name)", detail: screenDescription(span.attributes))
      print("[otel] \(event.title) | \(event.detail)")
      sink(event)
    }
    return .success
  }

  func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {}
}
