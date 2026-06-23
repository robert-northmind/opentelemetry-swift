/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import GRPC
import Logging
import NIO
import NIOHPACK
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetrySdk

public final class OtlpLogExporter: LogRecordExporter, @unchecked Sendable {
  let channel: GRPCChannel
  let logClient: Opentelemetry_Proto_Collector_Logs_V1_LogsServiceNIOClient
  let config: OtlpConfiguration
  // Immutable base options captured at init. `export` derives a per-call copy
  // with the desired timeLimit rather than mutating a shared instance field,
  // so concurrent calls cannot race on `callOptions`.
  let callOptions: CallOptions

  public init(channel: GRPCChannel,
              config: OtlpConfiguration = OtlpConfiguration(),
              logger: Logging.Logger = Logging.Logger(label: "io.grpc", factory: { _ in SwiftLogNoOpLogHandler() }),
              envVarHeaders: [(String, String)]? = EnvVarHeaders.attributes) {
    self.channel = channel
    logClient = Opentelemetry_Proto_Collector_Logs_V1_LogsServiceNIOClient(channel: channel)
    self.config = config
    let userAgentHeader = (Constants.HTTP.userAgent, Headers.getUserAgentHeader())
    if let headers = envVarHeaders {
      var updatedHeaders = headers
      updatedHeaders.append(userAgentHeader)
      callOptions = CallOptions(customMetadata: HPACKHeaders(updatedHeaders), logger: logger)
    } else if let headers = config.headers {
      var updatedHeaders = headers
      updatedHeaders.append(userAgentHeader)
      callOptions = CallOptions(customMetadata: HPACKHeaders(updatedHeaders), logger: logger)
    } else {
      var headers = [(String, String)]()
      headers.append(userAgentHeader)
      callOptions = CallOptions(customMetadata: HPACKHeaders(headers), logger: logger)
    }
  }

  public func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval? = nil) -> ExportResult {
    let logRequest = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest.with { request in
      request.resourceLogs = LogRecordAdapter.toProtoResourceRecordLog(logRecordList: logRecords)
    }
    let timeout = min(explicitTimeout ?? TimeInterval.greatestFiniteMagnitude, config.timeout)
    var perCallOptions = callOptions
    if timeout > 0 {
      perCallOptions.timeLimit = TimeLimit.timeout(TimeAmount.nanoseconds(Int64(timeout.toNanoseconds)))
    }

    let export = logClient.export(logRequest, callOptions: perCallOptions)
    do {
      _ = try export.response.wait()
      return .success
    } catch {
      return .failure
    }
  }

  public func shutdown(explicitTimeout: TimeInterval? = nil) {
    _ = channel.close()
  }

  public func forceFlush(explicitTimeout: TimeInterval? = nil) -> ExportResult {
    .success
  }
}
