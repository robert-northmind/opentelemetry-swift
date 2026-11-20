# Screen Tracking Demo

An iOS app for trying the experimental
[screen instrumentation](../../Sources/Instrumentation/Screen/README.md) on a simulator or device.
It navigates in every way SwiftUI and UIKit offer and shows what the instrumentation reports.

## Running

Open `ScreenTrackingDemo.xcodeproj` in Xcode 16 or later, select a development team under
*Signing & Capabilities*, and run. The project depends on the package at the repository root and
needs iOS 16.

## Reading the output

- The strip at the top shows the current screen and the last `app.navigation.complete` event with the
  mechanism that produced it. Sheets and full-screen covers hide it while they are up.
- The **Inspector** tab lists every event, span and log record the SDK produced.
- The same lines are printed to the Xcode console with an `[otel]` prefix.

## Switching mechanisms

The **Inspector** tab has two kinds of switches, both stored between launches:

- **Automatic detection**: the SDK's `detectsUIKitScreensAutomatically` and
  `detectsSwiftUIScreensAutomatically`. They apply at once; screens that are already visible are
  picked up the next time they appear.
- **Modifiers in this demo**: whether the `TabView` carries `.otelTrackTabs` and the Stack tab's
  `NavigationStack` carries `.otelTrackNavigation`, to show what automatic detection does without
  them. They apply on the next launch.

## Sending telemetry to a collector

By default the demo only shows its telemetry on screen. **Inspector → Export** sends it over
OTLP/HTTP as well:

- **OTLP collector**: any collector that accepts OTLP over HTTP, such as
  `http://<computer-ip>:4318`. Optional headers (one `Name: value` per line) are sent with every
  request, and `service.name` is configurable.
- **Grafana Frontend Observability**: the `/otlp/<app-key>` URL from **Settings → Mobile SDK Config →
  iOS**. No headers are needed; the app key in the URL is the credential. `service.name` is left
  out so Frontend Observability uses the app's registered name.

`/v1/traces` and `/v1/logs` are appended to the URL. Every record carries `session.id` (15 minute
inactivity timeout, 4 hour maximum, a new session on every launch), and `device.id` is removed from
the resource. The settings are stored on the device and apply on the next launch. Export errors
appear in the event list and in the console with an `[otel] export:` prefix. The app allows plain
HTTP so it can reach a collector on the local network.

## Tabs

| Tab | Navigation | Mechanism exercised |
| --- | --- | --- |
| Stack | `NavigationStack(path:)` with a typed path and one destination view type, links and programmatic pushes | `.otelTrackNavigation` taking over the stack from hosting detection |
| Links | `NavigationLink(destination:)`, with and without `.otelScreen()`, `AnyView`, a tracked screen that is slow to appear or redirects to a plain one, replacing the window's root view controller | `.otelScreen`, hosting detection |
| Modals | Sheet, full-screen cover, popover, alert, dialog, a checkout whose steps change by state, a `NavigationSplitView` with and without `.otelScreen` | `.otelScreen`, hosting detection, restoring the screen underneath |
| UIKit | Push, present, custom container, a child added after appearing, KVO, embedded and pushed `UIHostingController`, opted-out view controller, `viewDidAppear` called off the main thread | UIKit swizzling, `ScreenNameProviding` |
| Inspector | Opening and closing extra windows (iPad), another RUM tool that hooks `viewDidAppear` and `viewDidDisappear` the way some RUM SDKs do, started before or after OpenTelemetry and stopped at runtime | Automatic detection and modifier switches, OTLP export settings, sample span and log, `setScreen` and `clearScreen`, coexisting swizzles, event list |
