# Screen tracking watchOS demo

A small watchOS app that uses `ScreenInstrumentation` and shows the current screen at the top of
each list. watchOS has no UIKit, so automatic detection does not apply; screens are named through
the SwiftUI modifiers and manual calls:

| Screen | Mechanism | Name |
| --- | --- | --- |
| Workouts stack | `.otelTrackNavigation(path:rootName:)` | `Workouts`, `workout`, `summary` |
| Settings sheet | `.otelScreen("Settings")` | `Settings` |
| Vertical page tabs | `.otelTrackTabs(selection:)` | `Tab.workouts`, `Tab.manual` |
| Manual tab buttons | `ScreenTracker.shared.setScreen(name:)`, `clearScreen()` | `Manual` |

Every screen change is printed to the console with an `[otel]` prefix.

## Running

Open `ScreenTrackingWatchDemo.xcodeproj` and run the `ScreenTrackingWatchDemo` scheme on a watchOS
simulator. The UI test walks through every screen above and checks the name after each step:

```sh
xcodebuild test -scheme ScreenTrackingWatchDemo \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)'
```
