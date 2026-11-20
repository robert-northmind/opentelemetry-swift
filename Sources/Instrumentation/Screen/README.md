# Screen Instrumentation

Experimental. Tracks which screen the user is looking at in UIKit and SwiftUI apps, adds it to
every span and log record, and emits an event whenever it changes.

With no code in the app's views, UIKit view controllers are named after their class. SwiftUI
screens are named through SwiftUI modifiers, one line per `NavigationStack`, `TabView` or screen,
or, opt-in, automatically after their view type. Manual calls cover anything else.

The platform-independent core is covered by unit tests.

## Telemetry

- `app.screen.name` on every span (set at span start) and every log record, unless it already has one.
- A log event named `app.navigation.complete` for each screen change, with:
  - `app.navigation.destination.name` and `app.screen.name`: the screen that became current.
  - `app.screen.previous.name`: the screen before it, absent on the first event.
  - `app.screen.source`: the mechanism that detected the screen (see below).

Only `app.screen.name` is a semantic convention today
([semantic-conventions#2474](https://github.com/open-telemetry/semantic-conventions/issues/2474)
proposes a previous-screen attribute). `app.navigation.complete`, `app.navigation.destination.name`
and `app.screen.previous.name` are OpenTelemetry Android's own conventions, used here so that both
SDKs report screen changes the same way. `app.screen.source` is specific to this instrumentation.

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

Automatic detection of UIKit screens is on by default. Automatic detection of SwiftUI screens is
off by default, because it reads SwiftUI internals (see
[SwiftUI hosting controllers](#swiftui-hosting-controllers-automatic-opt-in)). Each can be switched,
at install or at runtime:

```swift
ScreenInstrumentation.install(
  configuration: ScreenInstrumentationConfiguration(
    detectsUIKitScreensAutomatically: false,
    detectsSwiftUIScreensAutomatically: true
  )
)

// or at runtime
ScreenInstrumentation.setDetectsUIKitScreensAutomatically(false)
ScreenInstrumentation.setDetectsSwiftUIScreensAutomatically(true)
```

Both kinds of automatic detection use the same hooks on `UIViewController`. With both turned off
at install, no method is swizzled. With only SwiftUI detection on, the hooks are installed but
return straight away for view controllers that are not SwiftUI's. Hooks that are installed stay
installed when detection is turned off at runtime; they stop reporting.

## Detection mechanisms

| Mechanism | `app.screen.source` | Setup | Screen name |
| --- | --- | --- | --- |
| UIKit view controllers | `uikit` | None | Class name of the view controller |
| SwiftUI hosting controllers | `swiftui.hosting` | Opt-in | Type of the SwiftUI view shown |
| `.otelTrackNavigation` | `swiftui.navigation` | One line per `NavigationStack` | Derived from the top route of the path |
| `.otelTrackTabs` | `swiftui.tabs` | One line per `TabView` | Derived from the selected tab |
| `.otelScreen` | `swiftui.screen` | One line per screen | Explicit, or the view's type name |
| `setScreen(name:)` | `manual` | One call per change | Explicit |

UIKit detection is on unless turned off, and SwiftUI hosting controller detection is off unless
turned on, as shown above. The others report whenever the app uses them. When an explicit SwiftUI mechanism and automatic detection see the same screen,
the explicit name is used (see
[Explicit modifiers take over their screens](#explicit-modifiers-take-over-their-screens)).

### UIKit view controllers (automatic)

`viewDidAppear` and `viewDidDisappear` are swizzled on `UIViewController`. A view controller is
tracked when its class is defined in the app or one of its embedded frameworks. These are skipped:

- System view controllers, and navigation, tab bar, split view and page view controllers.
- Children of the app's own view controllers, such as panes, mini players and banners. They are a
  part of their parent's screen. Children of system containers (a navigation or tab bar
  controller) are screens.
- View controllers in windows above the normal level, such as toasts and HUDs.
- Subclasses that do not call `super.viewDidAppear(_:)`, which the swizzle cannot see.
- Appearance methods called off the main thread. That is an app bug; the calls are passed on to
  UIKit unchanged but not tracked.

Other SDKs can hook the same methods; see
[Using with other RUM SDKs](#using-with-other-rum-sdks).

A view controller can choose its own name, or opt out by returning `nil`. While an opted-out view
controller is shown, the screen it covers stays current.

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

By default an enum route is named after its case without associated values, so
`Route.product(id: 42)` is reported as `product`. Any other route or selection is named after its
type (`String`, `Int`, `UUID`, `ProductRoute`), never its value, which may carry data. Pass a
closure to choose names yourself. A `NavigationPath` is opaque and cannot be tracked this way; use
`.otelScreen()` on its destinations.

### SwiftUI screens

```swift
ProfileView()
  .otelScreen()            // reported as "ProfileView"
  .otelScreen("Profile")   // or with an explicit name
```

Inside a view's own `body`, pass a name: the modifier only sees what the body is built from,
such as a `List`, and falls back to the name of the source file. Apply the modifier to the
screen's outermost view, not to a row of a `List` or another lazy container, which appear and
disappear while scrolling.

This also covers content that changes without navigation: if the name passed to `.otelScreen(_:)`
changes while the view stays on screen, the new name is reported.

### SwiftUI hosting controllers (automatic, opt-in)

SwiftUI shows navigation destinations, sheets, full-screen covers, popovers and tabs in view
controllers of its own, which the UIKit swizzle also sees. Each is named after the SwiftUI view it
shows, so `NavigationLink { ArticleView() }` and
`.navigationDestination(for: Route.self) { ArticleView(route: $0) }` are reported as
`ArticleView`, including when the content is wrapped in `AnyView`. A sheet whose view wraps its
content in a `NavigationStack`, as in `.sheet { SettingsView() }`, is reported as `SettingsView`.
The columns of a `NavigationSplitView` are reported under the name of the view around it, as in
`MailView`, unless a modifier names one of the columns.

SwiftUI hosts most of this content as `AnyView`, so the view's type is read from SwiftUI's stored
properties through `Mirror`. Those are not public API. If a future SwiftUI release stores them
differently, names fall back to what is described below, and nothing breaks.

- A screen built inline, such as a `List` written directly in a `navigationDestination` or a
  `switch` over routes, has no type of its own. The screen it was pushed from stays current. Give
  such screens a view type, or use `.otelTrackNavigation` or `.otelScreen`.
- Navigation titles are not used as names by default: they are localized and may carry data or
  personal information. `usesTitleForHostingControllers: true` names the root of a navigation
  stack, a tab or a presentation that has no view type after its title.
- Content that changes inside one screen involves no view controller and is not seen. This
  includes the detail column of a `NavigationSplitView` showing a different selection; name it
  with a value that follows the selection, as in `.otelScreen("Folder.\(folder)")`.
- Alerts, confirmation dialogs, hosting controllers embedded in the app's own view controllers,
  and hosting controllers that only hold a `NavigationStack` or `TabView` are not screens.

### Explicit modifiers take over their screens

This matters only when automatic SwiftUI detection is on; the modifiers work without it.

`.otelScreen` and `.otelTrackNavigation` place an invisible view behind the modified view. Before
the screen appears, it finds the hosting controller it is in and marks it as named by the
modifier, so automatic detection does not report the same screen a second time:

- `.otelScreen` takes over its hosting controller, and the root of a `NavigationStack` directly
  inside it. Screens pushed from there are not affected.
- `.otelTrackNavigation` takes over every screen of the stack.

### Manual

```swift
ScreenTracker.shared.setScreen(name: "Onboarding")
ScreenTracker.shared.clearScreen()   // the screen underneath becomes current again
```

## Using with other RUM SDKs

Screen tracking hooks two methods: `viewDidAppear(_:)` and `viewDidDisappear(_:)` on
`UIViewController`. It installs the hooks once, when `ScreenInstrumentation.install()` runs, and
never removes them. SwiftUI detection hooks nothing: it reads hosting controllers through `Mirror`
and adds an empty, hidden view behind each view with `.otelScreen` or `.otelTrackNavigation`.

Other mobile RUM SDKs often hook the same two methods. Both keep working: each hook
calls the implementation that was in place before it, so every SDK sees every appearance, in
either install order.

The order matters when an SDK removes its hooks while the app runs. If it restores the
implementation it saved at install time, every hook installed after it is lost too. Some SDKs
do this when they are stopped at runtime. If screen tracking was installed after such an SDK,
UIKit screens are no longer tracked from then on, and the current screen
name stays on the last screen reported before the stop.

To avoid this:

- Call `ScreenInstrumentation.install()` before starting the other SDK.
- If the other SDK has to start first, do not stop it while the app runs.

Screen tracking never removes its own hooks, so it cannot break another SDK this way.

## How the current screen is resolved

Visible screens are kept in a stack ordered by when they were last reported. The most recent one is
current. When it is closed and nothing replaces it within the same turn of the main queue, the one
underneath becomes current again, which is what happens when a sheet is dismissed. When the last
screen goes away, the last known name is kept.

Some reports arrive before a transition has finished, and are held back until it has:

- SwiftUI calls `onAppear` on the screen underneath as soon as a back navigation or dismissal
  starts. Such a screen becomes current only once the screen on top has disappeared, so a
  cancelled back swipe produces no event.
- Tab bars and the app's root view are containers. They are current only while no screen inside
  them is known, and showing them again after a full-screen presentation does not replace the
  screen inside them.
- A view controller covered by one that is not tracked, such as one that opted out, keeps its name
  until a tracked screen appears. Only view controllers that are popped, dismissed or taken out of
  their window (when the window's root view controller is replaced) reveal the screen underneath.
- When the screen of another tab disappears, the screen of the tab being shown becomes current,
  also without `.otelTrackTabs`.
- View controllers that were removed while covered, for example by `popToRootViewController`,
  are forgotten rather than revealed.
- Turning off automatic detection while one of its screens is current makes the screen
  underneath current.
- There is one current screen for the whole app, not one per window. The screen that appeared
  last, in any window, is current. When a window is closed, its screens are forgotten and a screen
  of a remaining window becomes current.
