# Screen Instrumentation

Experimental prototype. Tracks which screen the user is looking at in UIKit and SwiftUI apps, adds
it to every span and log record, and emits an event whenever it changes.

The platform-independent core is covered by unit tests. The UIKit and SwiftUI layers have not yet
been verified on a device; `Examples/ScreenTrackingDemo` exists for that.

## Telemetry

- `app.screen.name` on every span (set at span start) and every log record.
- A log event named `app.screen.view` for each screen change, with:
  - `app.screen.name`: the screen that became current.
  - `app.screen.previous.name`: the screen before it, absent on the first event.
  - `app.screen.source`: the mechanism that detected the screen (see below).

Only `app.screen.name` is a semantic convention today. The event name and the other two attributes
are placeholders until the conventions define them
([semantic-conventions#2474](https://github.com/open-telemetry/semantic-conventions/issues/2474)).

`ScreenTracker.currentScreenName` changes as soon as a screen is reported. The event follows one
turn of the main queue later, so that several reports belonging to one navigation produce one
event. Its timestamp is the moment the screen was reported.

## Setup

```swift
import OpenTelemetrySdk
import ScreenInstrumentation

OpenTelemetry.registerTracerProvider(
  tracerProvider: TracerProviderBuilder()
    .add(spanProcessor: ScreenSpanProcessor())
    .build()
)
OpenTelemetry.registerLoggerProvider(
  loggerProvider: LoggerProviderBuilder()
    .with(processors: [ScreenLogRecordProcessor(nextProcessor: yourLogProcessor)])
    .build()
)
ScreenInstrumentation.install()
```

## Detection mechanisms

Each mechanism is a `ScreenSource`. Choose them with
`ScreenInstrumentationConfiguration(enabledSources:)`, or change them at runtime with
`ScreenInstrumentation.setEnabledSources(_:)`.

| Source | Setup | Screen name |
| --- | --- | --- |
| `uiKit` | None | Class name of the view controller |
| `swiftUINavigation` | One line per `NavigationStack` | Derived from the top route of the path |
| `swiftUITabs` | One line per `TabView` | Derived from the selected tab |
| `swiftUIScreen` | One line per screen | Explicit, or the view's type name |
| `swiftUIHosting` | None, off by default | View type, else navigation title |
| `manual` | One call per change | Explicit |

### UIKit view controllers (automatic)

`viewDidAppear` and `viewDidDisappear` are swizzled on `UIViewController`. A view controller is
tracked when its class is defined in the app or one of its embedded frameworks. System view
controllers and navigation, tab bar, split view and page view controllers are skipped.

A view controller can choose its own name, or opt out by returning `nil`:

```swift
extension CheckoutViewController: ScreenNameProviding {
  var screenName: String? { "Checkout" }
}
```

### SwiftUI navigation containers

SwiftUI has no app-wide hook for navigation, but a `NavigationStack` driven by a typed path and a
`TabView` driven by a selection can each be tracked with one line, without touching the screens:

```swift
NavigationStack(path: $path) { ... }
  .otelTrackNavigation(path: path, rootName: "ProductList")

TabView(selection: $tab) { ... }
  .otelTrackTabs(selection: tab)
```

By default the name is the route's description without its associated values, so
`Route.product(id: 42)` is reported as `product`. Pass a closure to choose names yourself. A
`NavigationPath` is opaque and cannot be tracked this way; use `.otelScreen()` on its destinations.

### SwiftUI screens

```swift
ProfileView()
  .otelScreen()            // reported as "ProfileView"
  .otelScreen("Profile")   // or with an explicit name
```

This also covers content that changes without navigation: if the name passed to `.otelScreen(_:)`
changes while the view stays on screen, the new name is reported.

### SwiftUI hosting controllers (automatic, experimental)

SwiftUI puts navigation destinations and sheets in view controllers of its own, which the UIKit
swizzle also sees. With `swiftUIHosting` enabled these are reported, named after the first
non-framework type found in the hosting controller's type name, or else after its navigation title.

This is best-effort and limited:

- Only public type names are inspected, not SwiftUI's private storage. Content that SwiftUI
  type-erases, which is expected for most navigation destinations and sheets, has no type name, so
  the title is all that is left. Titles are user-facing text and may contain dynamic values; turn
  the fallback off with `usesTitleForHostingControllers: false`.
- Tab switches and content that changes inside one screen involve no view controller and are not
  seen.
- A hosting controller that appears within `hostingSuppressionInterval` (1 second by default) after
  one of the explicit SwiftUI mechanisms reported a screen is ignored, so that one navigation is
  not reported under two names. This is a timing heuristic.

### Manual

```swift
ScreenTracker.shared.setScreen(name: "Onboarding")
```

## How the current screen is resolved

Visible screens are kept in a stack ordered by when they were last reported. The most recent one is
current. When it goes away and nothing replaces it within the same turn of the main queue, the one
underneath becomes current again, which is what happens when a sheet is dismissed. When the last
screen goes away, the last known name is kept.
