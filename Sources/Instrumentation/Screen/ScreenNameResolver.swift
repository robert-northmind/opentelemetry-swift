/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

/// Derives screen names from Swift type names and navigation values.
enum ScreenNameResolver {
  private static let systemModules: Set<String> = [
    "SwiftUI", "Swift", "UIKit", "Foundation", "AppKit", "Combine", "__C"
  ]

  /// Finds the first type that is not a framework wrapper in a module-qualified type name, as
  /// produced by `String(reflecting:)`.
  ///
  /// `SwiftUI.UIHostingController<SwiftUI.ModifiedContent<MyApp.HomeView, SwiftUI._PaddingLayout>>`
  /// resolves to `HomeView`. Returns `nil` when only framework types are found, which is the case
  /// for type-erased content such as `SwiftUI.AnyView`.
  static func screenName(fromTypeName typeName: String) -> String? {
    firstAppType(in: Substring(typeName))
  }

  /// A low-cardinality name for a navigation value: the text before any associated values or
  /// stored properties, so `product(id: 42)` becomes `product`.
  static func routeName(for value: Any) -> String {
    let description = String(describing: value)
    let head = description.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
    return head.isEmpty ? String(describing: type(of: value)) : head
  }

  private static func firstAppType(in text: Substring) -> String? {
    let text = text.trimmingCharacters(in: .whitespaces)[...]
    guard let first = text.first, first != "(", first != "[" else { return nil }
    guard let open = text.firstIndex(of: "<") else {
      return appTypeName(text)
    }
    let head = text[..<open]
    guard isSystemType(head) else {
      return appTypeName(head)
    }
    for argument in genericArguments(of: text, openingAt: open) {
      if let name = firstAppType(in: argument) {
        return name
      }
    }
    return nil
  }

  private static func isSystemType(_ qualifiedName: Substring) -> Bool {
    guard let dot = qualifiedName.firstIndex(of: ".") else { return false }
    return systemModules.contains(String(qualifiedName[..<dot]))
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
