/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI

/// Presentations and in-place content changes.
///
/// When a tracked modal is dismissed, the screen underneath should become current again.
struct ModalsTab: View {
  @State private var showsTrackedSheet = false
  @State private var showsUntrackedSheet = false
  @State private var showsCover = false
  @State private var showsPopover = false
  @State private var showsAlert = false
  @State private var showsDialog = false
  @State private var showsSplitView = false
  @State private var showsTrackedSplitView = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          Explanation("Dismiss each presentation and check that the screen goes back to "
            + "ModalsRoot.")
        }
        Section("State-driven content") {
          NavigationLink("Checkout with steps") { CheckoutView() }
        }
        Section("Presentations") {
          Button("Sheet with .otelScreen()") { showsTrackedSheet = true }
          Button("Sheet without modifier") { showsUntrackedSheet = true }
          Button("Full-screen cover with .otelScreen()") { showsCover = true }
          Button("Popover with .otelScreen()") { showsPopover = true }
            .popover(isPresented: $showsPopover) {
              ModalContent(title: "Popover") { showsPopover = false }
                .otelScreen("Popover")
            }
        }
        Section("Columns") {
          Button("Sidebar and detail (NavigationSplitView)") { showsSplitView = true }
          Button("Sidebar and detail with .otelScreen()") { showsTrackedSplitView = true }
        }
        Section("Not screens (should emit nothing)") {
          Button("Alert") { showsAlert = true }
          Button("Confirmation dialog") { showsDialog = true }
        }
      }
      .navigationTitle("Modals")
      .otelScreen("ModalsRoot")
      .sheet(isPresented: $showsTrackedSheet) {
        ModalContent(title: "Tracked sheet") { showsTrackedSheet = false }
          .otelScreen("TrackedSheet")
      }
      .sheet(isPresented: $showsUntrackedSheet) {
        ModalContent(title: "Untracked sheet") { showsUntrackedSheet = false }
      }
      .fullScreenCover(isPresented: $showsCover) {
        ModalContent(title: "Cover") { showsCover = false }
          .otelScreen("FullScreenCover")
      }
      .fullScreenCover(isPresented: $showsSplitView) {
        MailSplitView(tracksColumns: false) { showsSplitView = false }
      }
      .fullScreenCover(isPresented: $showsTrackedSplitView) {
        MailSplitView(tracksColumns: true) { showsTrackedSplitView = false }
      }
      .alert("Alert", isPresented: $showsAlert) {
        Button("OK") {}
      }
      .confirmationDialog("Dialog", isPresented: $showsDialog) {
        Button("OK") {}
      }
    }
  }
}

/// One screen whose content changes without any navigation. No view controller appears when the
/// step changes, so only `.otelScreen(_:)` with a name that follows the state can see the steps.
struct CheckoutView: View {
  private enum Step: String, CaseIterable {
    case address
    case payment
    case review
  }

  @State private var step = Step.address
  @State private var tracksSteps = true

  var body: some View {
    List {
      Explanation("The name passed to .otelScreen() follows the step. Without it, automatic "
        + "detection sees one screen, CheckoutView.")
      Toggle("Track steps with .otelScreen()", isOn: $tracksSteps)
      Picker("Step", selection: $step) {
        ForEach(Step.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      Text("Checkout step: \(step.rawValue)")
    }
    .navigationTitle("Checkout")
    .otelScreen(tracksSteps ? "Checkout.\(step.rawValue)" : "Checkout")
  }
}

struct ModalContent: View {
  let title: String
  let dismiss: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Button("Dismiss", action: dismiss)
        NavigationLink("Push inside the modal") {
          Text("Pushed inside \(title)")
            .navigationTitle("Inside \(title)")
            .otelScreen("\(title).Pushed")
        }
      }
      .navigationTitle(title)
    }
  }
}

/// A sidebar and a detail column. Automatic detection does not name them: the sidebar is a system
/// `List`, and the detail column changes its content in place without a new view controller
/// appearing. With `tracksColumns`, `.otelScreen` names both, and the detail name follows the
/// selection.
struct MailSplitView: View {
  let tracksColumns: Bool
  let close: () -> Void
  @State private var folder: String?

  private let folders = ["Inbox", "Archive", "Trash"]

  var body: some View {
    NavigationSplitView {
      List(folders, id: \.self, selection: $folder) { Text($0) }
        .navigationTitle("Folders")
        .toolbar { Button("Close", action: close) }
        .applying(tracksColumns) { $0.otelScreen("Folders") }
    } detail: {
      if let folder {
        FolderView(name: folder)
          .applying(tracksColumns) { $0.otelScreen("Folder.\(folder)") }
      } else {
        Text("Pick a folder")
      }
    }
  }
}

struct FolderView: View {
  let name: String

  var body: some View {
    List {
      Explanation("Folder \(name).")
    }
    .navigationTitle(name)
  }
}
