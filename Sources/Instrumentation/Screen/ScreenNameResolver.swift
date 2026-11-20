/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Derives screen names from Swift type names and navigation values.
enum ScreenNameResolver {
  /// Modules whose types are never the app's screens. Modules whose name starts with an
  /// underscore, such as `_MapKit_SwiftUI`, are system modules too.
  private static let systemModules: Set<String> = [
    "Swift", "SwiftUI", "UIKit", "AppKit", "WatchKit", "Foundation", "Combine", "Observation",
    "SwiftData", "__C", "AVKit", "Charts", "ContactsUI", "EventKitUI", "GameKit", "HealthKitUI",
    "LinkPresentation", "MapKit", "MessageUI", "PassKit", "PhotosUI", "QuickLook", "RealityKit",
    "SafariServices", "SceneKit", "SpriteKit", "StoreKit", "TipKit", "WebKit", "WidgetKit",
    "AuthenticationServices", "ScreenInstrumentation", "OpenTelemetryApi", "OpenTelemetrySdk"
  ]

  /// System types that only wrap the view a hosting controller shows. For the generic ones, the
  /// first generic argument is the wrapped view, except for those in
  /// `wrappersOfLastGenericArgument`.
  private static let hostedViewWrappers: Set<String> = [
    "ModifiedContent", "Optional", "AnyView", "AnyViewStorage", "LazyView", "SheetContent",
    "ParameterizedLazyView"
  ]

  /// `ParameterizedLazyView<Route, Content>` holds a `navigationDestination(for:)` destination.
  private static let wrappersOfLastGenericArgument: Set<String> = ["ParameterizedLazyView"]

  /// Whether the module-qualified type name is a system type that only wraps another view.
  static func isHostedViewWrapper(_ typeName: String) -> Bool {
    let head = typeName.prefix { $0 != "<" }
    guard isSystemType(head) else { return false }
    return hostedViewWrappers.contains(simpleName(of: head))
  }

  private static func simpleName(of qualifiedName: Substring) -> String {
    qualifiedName.split(separator: ".").last.map(String.init) ?? ""
  }

  /// Finds the view in a module-qualified type name, as produced by `String(reflecting:)`, by
  /// unwrapping modifiers, optionals, `AnyView` storage and hosting controllers.
  ///
  /// `SwiftUI.UIHostingController<SwiftUI.ModifiedContent<MyApp.HomeView, SwiftUI._PaddingLayout>>`
  /// resolves to `HomeView`. It does not look inside other system views: content built from
  /// `List`, `VStack` and the like resolves to `nil` rather than to a view or modifier nested in
  /// it, which would name the screen after one of its parts. Type-erased content such as
  /// `SwiftUI.AnyView` also resolves to `nil`.
  static func viewName(fromTypeName typeName: String) -> String? {
    var text = Substring(typeName).trimmingCharacters(in: .whitespaces)[...]
    while true {
      guard let first = text.first, first != "(", first != "[" else { return nil }
      guard let open = text.firstIndex(of: "<") else {
        return appTypeName(text)
      }
      let head = text[..<open]
      guard isSystemType(head) else {
        return appTypeName(head)
      }
      let name = simpleName(of: head)
      let isWrapper = hostedViewWrappers.contains(name) || name.hasSuffix("HostingController")
      let arguments = genericArguments(of: text, openingAt: open)
      let wrapped = wrappersOfLastGenericArgument.contains(name) ? arguments.last : arguments.first
      guard isWrapper, let argument = wrapped else {
        return nil
      }
      text = argument.trimmingCharacters(in: .whitespaces)[...]
    }
  }

  /// The base name of a source file given as `#fileID` (`MyApp/ProfileView.swift` becomes
  /// `ProfileView`).
  static func fileName(fromFileID fileID: String) -> String {
    let file = fileID.split(separator: "/").last.map(String.init) ?? fileID
    return file.hasSuffix(".swift") ? String(file.dropLast(".swift".count)) : file
  }

  /// A low-cardinality name for a navigation value that never includes the data it carries.
  /// An enum case is named after the case, without associated values, so `product(id: 42)`
  /// becomes `product`. Any other value is named after its type (`ProductRoute`, `String`,
  /// `Int`), because its description would carry the value itself.
  static func routeName(for value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .enum else {
      return String(describing: type(of: value))
    }
    // A case with associated values has one child, labeled with the case name.
    if let label = mirror.children.first?.label {
      return label
    }
    let description = String(describing: value)
    let head = description.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
    return head.isEmpty ? String(describing: type(of: value)) : head
  }

  private static func isSystemType(_ qualifiedName: Substring) -> Bool {
    guard let dot = qualifiedName.firstIndex(of: ".") else { return false }
    let module = qualifiedName[..<dot]
    return module.hasPrefix("_") || systemModules.contains(String(module))
  }

  private static func appTypeName(_ qualifiedName: Substring) -> String? {
    guard !isSystemType(qualifiedName) else { return nil }
    let name = qualifiedName.split(separator: ".").last.map(String.init) ?? ""
    guard !name.isEmpty, !name.hasPrefix("_"), !name.hasPrefix("(") else { return nil }
    return name
  }

  /// Splits the top-level generic arguments of the list opening at `open`.
  private static func genericArguments(of text: Substring, openingAt open: Substring.Index) -> [Substring] {
    var arguments: [Substring] = []
    var depth = 0
    var start = text.index(after: open)
    var index = open
    var previous: Character?
    while index < text.endIndex {
      let character = text[index]
      switch character {
      case "<", "(", "[":
        depth += 1
      case ">" where previous == "-":
        break
      case ">", ")", "]":
        depth -= 1
        if depth == 0 {
          arguments.append(text[start ..< index])
          return arguments
        }
      case "," where depth == 1:
        arguments.append(text[start ..< index])
        start = text.index(after: index)
      default:
        break
      }
      previous = character
      index = text.index(after: index)
    }
    return arguments
  }
}
