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

  /// Whether the object behind a screen still exists and is part of the app's UI. Used to drop
  /// screens that went away without being reported, such as view controllers removed from a
  /// navigation stack while they were covered.
  typealias Liveness = @Sendable () -> Bool

  private struct Entry {
    let id: ScreenID
    let name: String
    let source: ScreenSource
    var isAlive: Liveness?
    /// Whether the entry stands for a container (a tab bar, the app's root view) rather than a
    /// screen. Containers give way to any screen shown inside them.
    var isContainer = false
    /// Whether the screen was hidden by something the tracker cannot see, such as a view
    /// controller that is not tracked. Its name is kept as the best guess until a known screen
    /// shows up.
    var isCovered = false
  }

  private struct Change {
    let name: String
    let previousName: String?
    let source: ScreenSource
    let time: Date
  }

  /// Screens that are covered but never shown again stay in the stack; this bounds it.
  private static let maximumEntries = 64

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
  var enabledSources: Set<ScreenSource> {
    get { lock.withLock { sources } }
    set { updateEnabledSources { $0 = newValue } }
  }

  /// Changes the enabled sources in one step. Screens from sources that are switched off are
  /// forgotten, and if the current screen was one of them, the screen underneath takes over.
  func updateEnabledSources(_ update: (inout Set<ScreenSource>) -> Void) {
    let needsFlush: Bool = lock.withLock {
      update(&sources)
      let enabled = sources
      entries.removeAll { !enabled.contains($0.source) }
      guard let current, !enabled.contains(current.source) else { return false }
      return claimFlush()
    }
    if needsFlush {
      scheduler { [weak self] in self?.flush() }
    }
  }

  /// Sets the current screen by hand. Use this where none of the other mechanisms apply.
  public func setScreen(name: String) {
    screenAppeared(id: .manual, name: name, source: .manual)
  }

  /// Removes the screen set with `setScreen(name:)`. The screen that was current before it, if
  /// any is still visible, becomes current again.
  public func clearScreen() {
    screenDisappeared(id: .manual)
  }

  /// Reports that a screen became visible, or that an already visible screen changed its name.
  func screenAppeared(id: ScreenID, name: String, source: ScreenSource) {
    report(id: id, name: name, source: source, isReappearing: false)
  }

  /// - Parameters:
  ///   - isReappearing: The screen is showing again because what covered it is going away, and
  ///     is reported before that has finished (SwiftUI's `onAppear` runs at the start of a
  ///     transition). It becomes current only if no screen is current; otherwise it waits
  ///     underneath until the covering screen disappears, so that a cancelled back swipe does not
  ///     produce an event.
  ///   - isContainer: The entry stands for a container such as a tab bar or the app's root view
  ///     rather than a screen. A reappearing screen replaces a current container.
  ///   - isAlive: Tells whether the screen still exists, for screens that can go away without
  ///     being reported.
  func report(id: ScreenID,
              name: String,
              source: ScreenSource,
              isReappearing: Bool = false,
              isContainer: Bool = false,
              isAlive: Liveness? = nil) {
    let needsFlush: Bool = lock.withLock {
      guard sources.contains(source) else { return false }
      let entry = Entry(id: id, name: name, source: source, isAlive: isAlive, isContainer: isContainer)
      entries.removeAll { $0.id == id }
      entries.append(entry)
      // A reappearing screen waits underneath while the screen on top is still visible. It
      // takes over from a container, and from a screen that is already hidden (when switching
      // tabs, for example, the previous tab's screen may disappear before or after this one
      // appears).
      if !isReappearing || current == nil || current?.id == id
        || current?.isContainer == true || current?.isCovered == true {
        makeCurrent(entry, at: clock())
      }
      return claimFlush()
    }
    if needsFlush {
      scheduler { [weak self] in self?.flush() }
    }
  }

  /// Reports that a screen is no longer visible.
  func screenDisappeared(id: ScreenID) {
    screenDisappeared(id: id, isCovered: false)
  }

  /// - Parameter isCovered: The screen is still there but hidden by something on top of it, as
  ///   opposed to being closed. When the screen on top is not tracked, the covered screen's name
  ///   stays current instead of the one underneath it.
  func screenDisappeared(id: ScreenID, isCovered: Bool) {
    let needsFlush: Bool = lock.withLock {
      if isCovered {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries[index].isCovered = true
        guard current?.id == id else { return false }
        current = entries[index]
        // A screen that appeared while this one was still visible is waiting to take over.
        return entries.last?.id != id && claimFlush()
      }
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

  /// Checks again which screens still exist, for when screens can go away without being
  /// reported, such as when a window is closed. If the current screen is gone, the screen
  /// underneath becomes current.
  func revalidate() {
    let needsFlush = lock.withLock { claimFlush() }
    if needsFlush {
      scheduler { [weak self] in self?.flush() }
    }
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
    // Asking whether screens are still alive may call into UIKit, so it happens outside `lock`.
    let liveness = lock.withLock { entries.map { ($0.id, $0.isAlive) } }
    let deadIDs = Set(liveness.compactMap { id, isAlive in isAlive?() == false ? id : nil })
    let change: Change? = lock.withLock {
      isFlushScheduled = false
      entries.removeAll { deadIDs.contains($0.id) }
      if let current {
        if let index = entries.firstIndex(where: { $0.id == current.id }) {
          // Hidden by a screen that has since been reported: that one takes over.
          if entries[index].isCovered, let top = entries.last, top.id != current.id, !top.isCovered {
            makeCurrent(top, at: clock())
          }
        } else if let top = entries.last(where: { !$0.isContainer && !$0.isCovered }) ?? entries.last {
          // The current screen went away and nothing replaced it: the one underneath shows
          // again, in preference to a container that only stands in for it. When that one is
          // covered by a screen the tracker does not know, its name is kept. With nothing
          // underneath, the last known name stays.
          makeCurrent(top, at: clock())
        }
      }
      if entries.count > Self.maximumEntries {
        entries.removeFirst(entries.count - Self.maximumEntries)
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
      ScreenConstants.navigationDestinationName: .string(change.name),
      SemanticConventions.App.screenName.rawValue: .string(change.name),
      ScreenConstants.screenSource: .string(change.source.rawValue)
    ]
    if let previousName = change.previousName {
      attributes[ScreenConstants.previousScreenName] = .string(previousName)
    }
    let provider = loggerProvider ?? OpenTelemetry.instance.loggerProvider
    provider.get(instrumentationScopeName: ScreenConstants.instrumentationScopeName)
      .logRecordBuilder()
      .setEventName(ScreenConstants.navigationCompleteEvent)
      .setTimestamp(change.time)
      .setAttributes(attributes)
      .emit()
  }
}
