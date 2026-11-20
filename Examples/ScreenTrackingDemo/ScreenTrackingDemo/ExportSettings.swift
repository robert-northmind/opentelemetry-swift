/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import SwiftUI

/// Where the demo sends its telemetry, besides the on-screen log. Read at launch.
struct ExportSettings: Codable, Equatable {
  enum Destination: String, Codable, CaseIterable, Identifiable {
    case off
    case collector
    case grafana

    var id: String { rawValue }

    var title: String {
      switch self {
      case .off: return "Off"
      case .collector: return "OTLP collector"
      case .grafana: return "Grafana Frontend Observability"
      }
    }
  }

  var destination = Destination.off
  /// The base OTLP/HTTP URL. `/v1/traces` and `/v1/logs` are appended.
  var endpoint = ""
  /// One `Name: value` header per line, for collectors that need authentication.
  var headers = ""
  var serviceName = "ScreenTrackingDemo"
  var environment = "development"

  private static let defaultsKey = "exportSettings"

  /// The settings the app was launched with.
  static let atLaunch = load()

  static func load() -> ExportSettings {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let settings = try? JSONDecoder().decode(ExportSettings.self, from: data) else {
      return ExportSettings()
    }
    return settings
  }

  func save() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
  }

  /// The base URL without a trailing signal path, or `nil` when it is not a valid http(s) URL.
  var baseURL: URL? {
    var text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    for suffix in ["/v1/traces", "/v1/logs", "/"] where text.hasSuffix(suffix) {
      text.removeLast(suffix.count)
    }
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https", url.host != nil else {
      return nil
    }
    return url
  }

  var parsedHeaders: [(String, String)] {
    headers.split(whereSeparator: \.isNewline).compactMap { line in
      guard let colon = line.firstIndex(of: ":") else { return nil }
      let name = line[..<colon].trimmingCharacters(in: .whitespaces)
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      return name.isEmpty ? nil : (name, value)
    }
  }

  /// Why the settings cannot be used, if they cannot.
  var problem: String? {
    guard destination != .off else { return nil }
    guard let baseURL else { return "Enter an http:// or https:// URL." }
    if destination == .grafana, !baseURL.path.contains("/otlp/") {
      return "Use the /otlp/<app-key> URL from Frontend Observability → Settings → Mobile SDK Config → iOS, "
        + "not the /collect/ URL."
    }
    return nil
  }

  var isExporting: Bool {
    destination != .off && problem == nil
  }
}

/// Edits `ExportSettings`. Changes apply on the next launch.
struct ExportSettingsView: View {
  @State private var settings = ExportSettings.load()
  @State private var isSaved = true

  var body: some View {
    Form {
      Section {
        Picker("Destination", selection: $settings.destination) {
          ForEach(ExportSettings.Destination.allCases) { Text($0.title).tag($0) }
        }
      } footer: {
        Text(destinationHelp)
      }

      if settings.destination != .off {
        Section {
          TextField(endpointPlaceholder, text: $settings.endpoint, axis: .vertical)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.callout.monospaced())
        } header: {
          Text("Endpoint")
        } footer: {
          if let problem = settings.problem {
            Text(problem).foregroundStyle(.red)
          } else if let url = settings.baseURL {
            Text("Sends to \(url.appending(path: "v1/traces").absoluteString) and …/v1/logs")
          }
        }

        if settings.destination == .collector {
          Section {
            TextField("Authorization: Basic …", text: $settings.headers, axis: .vertical)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .font(.callout.monospaced())
          } header: {
            Text("Headers (optional)")
          } footer: {
            Text("One \"Name: value\" per line.")
          }
          Section("service.name") {
            TextField("ScreenTrackingDemo", text: $settings.serviceName)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
        }

        Section("deployment.environment.name") {
          TextField("development", text: $settings.environment)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }

      Section {
        Button("Save") {
          settings.save()
          isSaved = true
        }
        .disabled(isSaved || settings.problem != nil)
        Button("Quit the app to apply", role: .destructive) {
          settings.save()
          exit(0)
        }
        .disabled(settings == ExportSettings.atLaunch)
      } footer: {
        Text("Settings are stored on this device and apply the next time the app starts. "
          + "Running now: \(Telemetry.exportDescription)")
      }
    }
    .navigationTitle("Export")
    .onChange(of: settings) { _ in isSaved = false }
  }

  private var destinationHelp: String {
    switch settings.destination {
    case .off:
      return "Telemetry is only shown in the app."
    case .collector:
      return "Any OpenTelemetry collector that accepts OTLP over HTTP, such as http://<laptop-ip>:4318."
    case .grafana:
      return "Frontend Observability → your app → Settings → Mobile SDK Config → iOS. The app key in the URL "
        + "is the credential; no headers are needed."
    }
  }

  private var endpointPlaceholder: String {
    settings.destination == .grafana
      ? "https://faro-collector-<region>.grafana.net/otlp/<app-key>"
      : "http://192.168.1.10:4318"
  }
}
