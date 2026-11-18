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
  private enum Step: String, CaseIterable {
    case address
    case payment
    case review
  }

  @State private var showsTrackedSheet = false
  @State private var showsUntrackedSheet = false
  @State private var showsCover = false
  @State private var showsPopover = false
  @State private var showsAlert = false
  @State private var showsDialog = false
  @State private var step = Step.address
  @State private var tracksSteps = true

  var body: some View {
    NavigationStack {
      List {
        Section {
          Explanation("Dismiss each presentation and check that the screen goes back to "
            + "ModalsRoot.")
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
        Section("Not screens (should emit nothing)") {
          Button("Alert") { showsAlert = true }
          Button("Confirmation dialog") { showsDialog = true }
        }
        Section("State-driven content swap") {
          Explanation("One screen whose content changes without any navigation. No view "
            + "controller appears, so only .otelScreen() can see the steps.")
          Toggle("Track steps with .otelScreen()", isOn: $tracksSteps)
          Picker("Step", selection: $step) {
            ForEach(Step.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          stepContent
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
      .alert("Alert", isPresented: $showsAlert) {
        Button("OK") {}
      }
      .confirmationDialog("Dialog", isPresented: $showsDialog) {
        Button("OK") {}
      }
    }
  }

  @ViewBuilder
  private var stepContent: some View {
    if tracksSteps {
      Text("Checkout step: \(step.rawValue)")
        .otelScreen("Checkout.\(step.rawValue)")
    } else {
      Text("Checkout step: \(step.rawValue)")
    }
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
