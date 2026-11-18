/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

/// Holds the screen the user is currently looking at and emits an event whenever it changes.
///
/// Every detection mechanism (UIKit swizzling, the SwiftUI modifiers, manual calls) reports into
/// the same tracker. Visible screens are kept in a stack ordered by when they were last reported,
/// so that when the top screen goes away (a dismissed sheet, for example) the one underneath
/// becomes current again.
///
/// `currentScreenName` changes as soon as a screen is reported. The screen-view event is emitted
/// one turn of the main queue later, so that several reports belonging to one navigation (a tab
/// switch followed by the stack inside that tab, or an old screen disappearing just before the
/// new one appears) produce a single event.
public final class ScreenTracker: @unchecked Sendable {
  public static let shared = ScreenTracker()

  typealias Scheduler = @Sendable (@escaping @Sendable () -> Void) -> Void

  private struct Entry {
    let id: ScreenID
    let name: String
    let source: ScreenSource
  }

  private struct Change {
    let name: String
    let previousName: String?
    let source: ScreenSource
    let time: Date
  }

  private let lock = NSLock()
  /// Serializes flushes so events leave in the order the changes happened. Separate from `lock`
  /// because processors read `currentScreenName` while an event is being emitted.
  private let flushLock = NSLock()
  private let loggerProvider: (any LoggerProvider)?
  private let clock: @Sendable () -> Date
  private let scheduler: Scheduler

  private var entries: [Entry] = []
  private var current: Entry?
  private var currentSince = Date()
  private var emittedName: String?
  private var isFlushScheduled = false
  private var sources: Set<ScreenSource> = Set(ScreenSource.allCases)
  private var suppressionInterval: TimeInterval = ScreenInstrumentationConfiguration.defaultHostingSuppressionInterval
  private var lastExplicitReport: Date?

  init(loggerProvider: (any LoggerProvider)? = nil,
       clock: @escaping @Sendable () -> Date = { Date() },
       scheduler: @escaping Scheduler = { DispatchQueue.main.async(execute: $0) }) {
    self.loggerProvider = loggerProvider
    self.clock = clock
    self.scheduler = scheduler
  }

  /// The name of the screen currently shown, or `nil` before the first screen is reported.
  public var currentScreenName: String? {
    lock.withLock { current?.name }
  }

  /// The detection mechanisms whose reports are accepted. Reports from other sources are dropped.
  public var enabledSources: Set<ScreenSource> {
    get { lock.withLock { sources } }
    set {
      lock.withLock {
        sources = newValue
        entries.removeAll { !newValue.contains($0.source) }
      }
    }
  }

  /// How long after an explicit SwiftUI report an automatically detected hosting controller is
  /// ignored, so that one navigation is not reported twice under two names.
  public var hostingSuppressionInterval: TimeInterval {
    get { lock.withLock { suppressionInterval } }
    set { lock.withLock { suppressionInterval = newValue } }
  }

  /// Sets the current screen by hand. Use this where none of the other mechanisms apply.
  public func setScreen(name: String) {
    screenAppeared(id: .manual, name: name, source: .manual)
  }

  /// Reports that a screen became visible, or that an already visible screen changed its name.
  public func screenAppeared(id: ScreenID, name: String, source: ScreenSource) {
    let needsFlush: Bool = lock.withLock {
      guard sources.contains(source) else { return false }
      let now = clock()
      if source == .swiftUIHosting,
         let lastExplicitReport,
         now.timeIntervalSince(lastExplicitReport) < suppressionInterval {
        return false
      }
      if source.isExplicit {
        lastExplicitReport = now
      }
      let entry = Entry(id: id, name: name, source: source)
      entries.removeAll { $0.id == id }
      entries.append(entry)
      makeCurrent(entry, at: now)
      return claimFlush()
    }
    if needsFlush {
      scheduler { [weak self] in self?.flush() }
    }
  }

  /// Reports that a screen is no longer visible.
  public func screenDisappeared(id: ScreenID) {
    let needsFlush: Bool = lock.withLock {
      entries.removeAll { $0.id == id }
      guard current?.id == id else { return false }
      return claimFlush()
    }
    if needsFlush {
      scheduler { [weak self] in self?.flush() }
    }
  }

  /// Must be called with `lock` held.
  private func makeCurrent(_ entry: Entry, at time: Date) {
    if current?.name != entry.name {
      currentSince = time
    }
    current = entry
  }

  /// Must be called with `lock` held. Returns whether the caller has to schedule a flush.
  private func claimFlush() -> Bool {
    guard !isFlushScheduled else { return false }
    isFlushScheduled = true
    return true
  }

  private func flush() {
    flushLock.lock()
    defer { flushLock.unlock() }
    let change: Change? = lock.withLock {
      isFlushScheduled = false
      // The current screen went away and nothing replaced it: the one underneath shows again.
      if let current, !entries.contains(where: { $0.id == current.id }), let top = entries.last {
        makeCurrent(top, at: clock())
      }
      guard let current, current.name != emittedName else { return nil }
      let change = Change(name: current.name, previousName: emittedName, source: current.source, time: currentSince)
      emittedName = current.name
      return change
    }
    if let change {
      emit(change)
    }
  }

  private func emit(_ change: Change) {
    var attributes: [String: AttributeValue] = [
      SemanticConventions.App.screenName.rawValue: .string(change.name),
      ScreenConstants.screenSource: .string(change.source.rawValue)
    ]
    if let previousName = change.previousName {
      attributes[ScreenConstants.previousScreenName] = .string(previousName)
    }
    let provider = loggerProvider ?? OpenTelemetry.instance.loggerProvider
    provider.get(instrumentationScopeName: ScreenConstants.instrumentationScopeName)
      .logRecordBuilder()
      .setEventName(ScreenConstants.screenViewEvent)
      .setTimestamp(change.time)
      .setAttributes(attributes)
      .emit()
  }
}
