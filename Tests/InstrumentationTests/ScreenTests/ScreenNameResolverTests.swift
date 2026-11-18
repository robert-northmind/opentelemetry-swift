/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import XCTest
@testable import ScreenInstrumentation

private enum Route: Hashable {
  case list
  case product(id: Int)
  case profile(String)
}

private struct ProductRoute: Hashable {
  let id: Int
}

private struct LocalView {}

private struct Wrapper<Content> {}

final class ScreenNameResolverTests: XCTestCase {
  func testPlainAppTypeDropsModule() {
    XCTAssertEqual(ScreenNameResolver.screenName(fromTypeName: "MyApp.HomeView"), "HomeView")
  }

  func testHostingControllerIsUnwrapped() {
    XCTAssertEqual(
      ScreenNameResolver.screenName(fromTypeName: "SwiftUI.UIHostingController<MyApp.HomeView>"),
      "HomeView"
    )
  }

  func testModifiedContentIsUnwrappedToItsContent() {
    let typeName = "SwiftUI.UIHostingController<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<MyApp.HomeView, "
      + "SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<MyApp.Model>>>, SwiftUI._PaddingLayout>>"

    XCTAssertEqual(ScreenNameResolver.screenName(fromTypeName: typeName), "HomeView")
  }

  func testFirstAppTypeWinsWhenFrameworkTypesComeFirst() {
    let typeName = "SwiftUI.ModifiedContent<SwiftUI.VStack<SwiftUI.TupleView<(SwiftUI.Text, SwiftUI.Text)>>, "
      + "MyApp.CardStyle>"

    XCTAssertEqual(ScreenNameResolver.screenName(fromTypeName: typeName), "CardStyle")
  }

  func testTypeErasedContentHasNoName() {
    XCTAssertNil(ScreenNameResolver.screenName(fromTypeName: "SwiftUI.UIHostingController<SwiftUI.AnyView>"))
    XCTAssertNil(
      ScreenNameResolver.screenName(fromTypeName: "SwiftUI.NavigationStackHostingController<SwiftUI.AnyView>")
    )
    XCTAssertNil(ScreenNameResolver.screenName(fromTypeName: "SwiftUI.AnyView"))
  }

  func testAppGenericTypeKeepsOuterName() {
    XCTAssertEqual(
      ScreenNameResolver.screenName(fromTypeName: "SwiftUI.UIHostingController<MyApp.LazyView<MyApp.DetailView>>"),
      "LazyView"
    )
  }

  func testNestedAndPrivateTypesUseInnermostName() {
    XCTAssertEqual(ScreenNameResolver.screenName(fromTypeName: "MyApp.Settings.AboutView"), "AboutView")
    XCTAssertEqual(
      ScreenNameResolver.screenName(fromTypeName: "MyApp.(unknown context at $1047d2f0c).HomeView"),
      "HomeView"
    )
  }

  func testFunctionTypeArrowDoesNotCloseGenericList() {
    let typeName = "SwiftUI.ModifiedContent<SwiftUI._ConditionalContent<SwiftUI.Text, "
      + "SwiftUI.Button<(Swift.Int) -> Swift.Void>>, MyApp.ScreenStyle>"

    XCTAssertEqual(ScreenNameResolver.screenName(fromTypeName: typeName), "ScreenStyle")
  }

  func testUnderscoredAndTupleTypesHaveNoName() {
    XCTAssertNil(ScreenNameResolver.screenName(fromTypeName: "MyApp._Hidden"))
    XCTAssertNil(ScreenNameResolver.screenName(fromTypeName: "(MyApp.A, MyApp.B)"))
    XCTAssertNil(ScreenNameResolver.screenName(fromTypeName: ""))
  }

  func testRealReflectedTypeNamesResolve() {
    XCTAssertEqual(ScreenNameResolver.screenName(fromTypeName: String(reflecting: LocalView.self)), "LocalView")
    XCTAssertEqual(
      ScreenNameResolver.screenName(fromTypeName: String(reflecting: Wrapper<LocalView>.self)),
      "Wrapper"
    )
    XCTAssertNil(ScreenNameResolver.screenName(fromTypeName: String(reflecting: [Int?].self)))
  }

  func testRouteNameDropsAssociatedValues() {
    XCTAssertEqual(ScreenNameResolver.routeName(for: Route.list), "list")
    XCTAssertEqual(ScreenNameResolver.routeName(for: Route.product(id: 42)), "product")
    XCTAssertEqual(ScreenNameResolver.routeName(for: Route.profile("jane")), "profile")
  }

  func testRouteNameForStructIsTypeName() {
    XCTAssertEqual(ScreenNameResolver.routeName(for: ProductRoute(id: 7)), "ProductRoute")
  }

  func testRouteNameForStringIsTheString() {
    XCTAssertEqual(ScreenNameResolver.routeName(for: "settings"), "settings")
  }
}
