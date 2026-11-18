# Screen Tracking Demo

An iOS app for trying the experimental
[screen instrumentation](../../Sources/Instrumentation/Screen/README.md) on a simulator or device.
It navigates in every way SwiftUI and UIKit offer and shows what the instrumentation reports.

## Running

Open `ScreenTrackingDemo.xcodeproj` in Xcode 16 or later, select a development team under
*Signing & Capabilities*, and run. The project depends on the package at the repository root and
needs iOS 16.

## Reading the output

- The strip at the top shows the current screen and the last `app.screen.view` event with the
  mechanism that produced it. Sheets and full-screen covers hide it while they are up.
- The **Inspector** tab lists every event, span and log record the SDK produced.
- The same lines are printed to the Xcode console with an `[otel]` prefix.

## Switching mechanisms

The **Inspector** tab has a switch per detection mechanism and presets for common combinations.
The choice is stored and applies immediately; screens that are already visible are picked up the
next time they appear.

| Preset | What it shows |
| --- | --- |
| Default | Everything except hosting-controller detection |
| Automatic only | What an app gets with no code in its views |
| Containers only | One line per `NavigationStack` and `TabView` |
| Per-screen only | `.otelScreen()` alone |
| Everything | All mechanisms at once, including duplicate suppression |

## Tabs

| Tab | Navigation | Mechanism exercised |
| --- | --- | --- |
| Stack | `NavigationStack(path:)` with a typed path, links and programmatic pushes | `.otelTrackNavigation` |
| Links | `NavigationLink(destination:)`, with and without `.otelScreen()`, `AnyView` | `.otelScreen`, hosting detection |
| Modals | Sheet, full-screen cover, popover, alert, dialog, content swapped by state | `.otelScreen`, restoring the screen underneath |
| UIKit | Push, present, custom container, embedded and pushed `UIHostingController` | UIKit swizzling, `ScreenNameProviding` |
| Inspector | | Toggles, sample span and log, event list |
