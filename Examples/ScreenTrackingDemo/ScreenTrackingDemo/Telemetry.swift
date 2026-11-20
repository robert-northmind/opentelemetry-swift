/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import ResourceExtension
import ScreenInstrumentation
import Sessions

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

  /// What the app exports to, besides the on-screen log, as set up at launch.
  nonisolated(unsafe) private(set) static var exportDescription = "on-screen log only"

  static func setUp(sink: @escaping @Sendable (DemoEvent) -> Void) {
    let export = ExportSettings.atLaunch
    var spanProcessors: [SpanProcessor] = [
      ScreenSpanProcessor(),
      SimpleSpanProcessor(spanExporter: DemoSpanExporter(sink: sink))
    ]
    var logProcessors: [LogRecordProcessor] = [
      ScreenLogRecordProcessor(
        nextProcessor: SimpleLogRecordProcessor(logRecordExporter: DemoLogExporter(sink: sink))
      )
    ]
    var resource: Resource?

    if export.isExporting, let baseURL = export.baseURL {
      OpenTelemetry.registerFeedbackHandler { message in
        NSLog("[otel] export: %@", message)
        sink(DemoEvent(kind: .log, title: "export: \(message)", detail: baseURL.host ?? ""))
      }
      // Every record carries session.id; Frontend Observability rejects batches without it.
      SessionManagerProvider.register(sessionManager: SessionManager(
        configuration: SessionConfig(sessionTimeout: 15 * 60,
                                     maxLifetime: 4 * 60 * 60,
                                     restorePersistedSession: false)
      ))
      var attributes = DefaultResources().get().attributes
      attributes.removeValue(forKey: "device.id")
      if export.destination == .grafana {
        // Frontend Observability names the app after its registration instead.
        attributes.removeValue(forKey: "service.name")
      } else {
        attributes["service.name"] = .string(export.serviceName)
      }
      attributes["deployment.environment.name"] = .string(export.environment)
      resource = Resource(attributes: attributes)

      let headers = export.parsedHeaders.isEmpty ? nil : export.parsedHeaders
      spanProcessors.insert(SessionSpanProcessor(), at: 0)
      spanProcessors.append(BatchSpanProcessor(
        spanExporter: OtlpHttpTraceExporter(endpoint: baseURL.appending(path: "v1/traces"), envVarHeaders: headers)
      ))
      logProcessors.append(ScreenLogRecordProcessor(
        nextProcessor: SessionLogRecordProcessor(
          nextProcessor: BatchLogRecordProcessor(
            logRecordExporter: OtlpHttpLogExporter(endpoint: baseURL.appending(path: "v1/logs"), envVarHeaders: headers)
          )
        )
      ))
      exportDescription = "\(export.destination.title), \(baseURL.host ?? "")"
    }

    var loggerProviderBuilder = LoggerProviderBuilder().with(processors: logProcessors)
    var tracerProviderBuilder = TracerProviderBuilder().add(spanProcessors: spanProcessors)
    if let resource {
      loggerProviderBuilder = loggerProviderBuilder.with(resource: resource)
      tracerProviderBuilder = tracerProviderBuilder.with(resource: resource)
    }
    OpenTelemetry.registerLoggerProvider(loggerProvider: loggerProviderBuilder.build())
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProviderBuilder.build())
    if export.isExporting {
      // After the logger provider, so session.start goes to the exporter.
      SessionEventInstrumentation.install()
    }
    ScreenInstrumentation.install(
      configuration: ScreenInstrumentationConfiguration(
        detectsUIKitScreensAutomatically: DemoSettings.detectsUIKitScreens,
        detectsSwiftUIScreensAutomatically: DemoSettings.detectsSwiftUIScreens
      )
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

/// Settings kept between launches: the SDK's automatic detection switches, and which of the
/// SwiftUI modifiers the demo applies (read at launch).
enum DemoSettings {
  static var detectsUIKitScreens: Bool {
    get { flag("detectsUIKitScreens") }
    set { UserDefaults.standard.set(newValue, forKey: "detectsUIKitScreens") }
  }

  static var detectsSwiftUIScreens: Bool {
    get { flag("detectsSwiftUIScreens") }
    set { UserDefaults.standard.set(newValue, forKey: "detectsSwiftUIScreens") }
  }

  /// Whether the TabView carries `.otelTrackTabs`.
  static var appliesTrackTabs: Bool {
    get { flag("appliesTrackTabs") }
    set { UserDefaults.standard.set(newValue, forKey: "appliesTrackTabs") }
  }

  /// Whether the Stack tab's NavigationStack carries `.otelTrackNavigation`.
  static var appliesTrackNavigation: Bool {
    get { flag("appliesTrackNavigation") }
    set { UserDefaults.standard.set(newValue, forKey: "appliesTrackNavigation") }
  }

  /// Every setting is on unless it was switched off.
  private static func flag(_ key: String) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? true
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
      if record.eventName == ScreenConstants.navigationCompleteEvent {
        let previous = record.attributes[ScreenConstants.previousScreenName]?.description ?? "<none>"
        let current = record.attributes[screenNameKey]?.description ?? "<none>"
        let source = record.attributes[ScreenConstants.screenSource]?.description ?? "<none>"
        event = DemoEvent(kind: .screenView, title: "\(previous) → \(current)", detail: "source: \(source)")
      } else {
        event = DemoEvent(kind: .log,
                          title: "log: \(record.body?.description ?? record.eventName ?? "<empty>")",
                          detail: screenDescription(record.attributes))
      }
      NSLog("[otel] %@ | %@", event.title, event.detail)
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
      NSLog("[otel] %@ | %@", event.title, event.detail)
      sink(event)
    }
    return .success
  }

  func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
    .success
  }

  func shutdown(explicitTimeout: TimeInterval?) {}
}
