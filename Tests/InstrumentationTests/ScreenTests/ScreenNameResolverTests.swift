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

private enum DescribedRoute: Hashable, CustomStringConvertible {
  case user(name: String)

  var description: String {
    switch self {
    case let .user(name): return "User \(name)"
    }
  }
}

private struct LocalView {}

private struct Wrapper<Content> {}

final class ScreenNameResolverTests: XCTestCase {
  func testPlainAppTypeDropsModule() {
    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: "MyApp.HomeView"), "HomeView")
  }

  func testHostingControllerIsUnwrapped() {
    XCTAssertEqual(
      ScreenNameResolver.viewName(fromTypeName: "SwiftUI.UIHostingController<MyApp.HomeView>"),
      "HomeView"
    )
  }

  func testModifiedContentIsUnwrappedToItsContent() {
    let typeName = "SwiftUI.UIHostingController<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<MyApp.HomeView, "
      + "SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<MyApp.Model>>>, SwiftUI._PaddingLayout>>"

    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: typeName), "HomeView")
  }

  func testSystemViewIsNotSearchedForAppTypes() {
    // Naming the screen after a modifier or a row inside it would be wrong.
    let modified = "SwiftUI.ModifiedContent<SwiftUI.VStack<SwiftUI.TupleView<(SwiftUI.Text, SwiftUI.Text)>>, "
      + "MyApp.CardStyle>"
    let list = "SwiftUI.List<Swift.Never, SwiftUI.TupleView<(MyApp.Row, MyApp.Row)>>"

    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: modified))
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: list))
  }

  func testOwnModifiersAreNotScreens() {
    let typeName = "SwiftUI.ModifiedContent<SwiftUI.Text, "
      + "ScreenInstrumentation.ScreenTrackingModifier<Swift.String>>"

    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: typeName))
  }

  func testAnyViewStorageIsUnwrapped() {
    // As reflected from the storage of a navigation destination's AnyView on iOS 26.
    let typeName = "SwiftUI.(unknown context at $1c7b5b5b0).AnyViewStorage<SwiftUI.ModifiedContent<"
      + "SwiftUI.ModifiedContent<Swift.Optional<MyApp.ArticleView>, "
      + "SwiftUI.(unknown context at $1ca66e438).ReadDestinationsModifier<SwiftUI.ResolvedNavigationDestinations>>, "
      + "SwiftUI._PreferenceTransformModifier<SwiftUI.NavigationDestinationKey>>>"

    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: typeName), "ArticleView")
  }

  func testSheetContentIsUnwrapped() {
    let typeName = "SwiftUI.(unknown context at $1c7b5b5b0).AnyViewStorage<SwiftUI.ModifiedContent<"
      + "SwiftUI.(unknown context at $1ca62cc98).SheetContent<MyApp.SettingsView>, "
      + "SwiftUI._EnvironmentKeyWritingModifier<SwiftUI.Binding<SwiftUI.PresentationMode>>>>"

    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: typeName), "SettingsView")
  }

  func testTypedDestinationIsFoundThroughParameterizedLazyView() {
    let single = "SwiftUI.ParameterizedLazyView<MyApp.Route, MyApp.CartView>"
    let branching = "SwiftUI.ParameterizedLazyView<MyApp.Route, SwiftUI._ConditionalContent<MyApp.A, MyApp.B>>"

    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: single), "CartView")
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: branching))
  }

  func testAppRootViewIsFoundThroughLazyView() {
    let typeName = "SwiftUI.UIHostingController<SwiftUI.ModifiedContent<SwiftUI.LazyView<"
      + "SwiftUI.ModifiedContent<MyApp.RootView, SwiftUI._EnvironmentKeyWritingModifier<"
      + "Swift.Optional<MyApp.Store>>>>, SwiftUI.RootModifier>>"

    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: typeName), "RootView")
  }

  func testWrapperDetection() {
    XCTAssertTrue(ScreenNameResolver.isHostedViewWrapper("SwiftUI.AnyView"))
    XCTAssertTrue(ScreenNameResolver.isHostedViewWrapper("SwiftUI.ModifiedContent<SwiftUI.AnyView, X>"))
    XCTAssertTrue(ScreenNameResolver.isHostedViewWrapper(
      "SwiftUI.(unknown context at $1c7b5b5b0).AnyViewStorage<SwiftUI.AnyView>"
    ))
    XCTAssertFalse(ScreenNameResolver.isHostedViewWrapper("SwiftUI.List<Swift.Never, MyApp.Row>"))
    XCTAssertFalse(ScreenNameResolver.isHostedViewWrapper("MyApp.AnyView"))
  }

  func testTypeErasedContentHasNoName() {
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: "SwiftUI.UIHostingController<SwiftUI.AnyView>"))
    XCTAssertNil(
      ScreenNameResolver.viewName(fromTypeName: "SwiftUI.NavigationStackHostingController<SwiftUI.AnyView>")
    )
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: "SwiftUI.AnyView"))
  }

  func testAppGenericTypeKeepsOuterName() {
    XCTAssertEqual(
      ScreenNameResolver.viewName(fromTypeName: "SwiftUI.UIHostingController<MyApp.LazyView<MyApp.DetailView>>"),
      "LazyView"
    )
  }

  func testNestedAndPrivateTypesUseInnermostName() {
    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: "MyApp.Settings.AboutView"), "AboutView")
    XCTAssertEqual(
      ScreenNameResolver.viewName(fromTypeName: "MyApp.(unknown context at $1047d2f0c).HomeView"),
      "HomeView"
    )
  }

  func testFunctionTypeArrowDoesNotCloseGenericList() {
    let typeName = "SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<MyApp.HomeView, "
      + "SwiftUI._Action<(Swift.Int) -> Swift.Void>>, SwiftUI._PaddingLayout>"

    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: typeName), "HomeView")
  }

  func testUnderscoredAndTupleTypesHaveNoName() {
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: "MyApp._Hidden"))
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: "(MyApp.A, MyApp.B)"))
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: ""))
  }

  func testRealReflectedTypeNamesResolve() {
    XCTAssertEqual(ScreenNameResolver.viewName(fromTypeName: String(reflecting: LocalView.self)), "LocalView")
    XCTAssertEqual(
      ScreenNameResolver.viewName(fromTypeName: String(reflecting: Wrapper<LocalView>.self)),
      "Wrapper"
    )
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: String(reflecting: [Int?].self)))
  }

  func testFileNameDropsModuleAndExtension() {
    XCTAssertEqual(ScreenNameResolver.fileName(fromFileID: "MyApp/ProfileView.swift"), "ProfileView")
    XCTAssertEqual(ScreenNameResolver.fileName(fromFileID: "Profile"), "Profile")
  }

  func testRouteNameDropsAssociatedValues() {
    XCTAssertEqual(ScreenNameResolver.routeName(for: Route.list), "list")
    XCTAssertEqual(ScreenNameResolver.routeName(for: Route.product(id: 42)), "product")
    XCTAssertEqual(ScreenNameResolver.routeName(for: Route.profile("jane")), "profile")
  }

  func testRouteNameForStructIsTypeName() {
    XCTAssertEqual(ScreenNameResolver.routeName(for: ProductRoute(id: 7)), "ProductRoute")
  }

  func testRouteNameNeverIncludesPlainValues() {
    XCTAssertEqual(ScreenNameResolver.routeName(for: "jane@example.com"), "String")
    XCTAssertEqual(ScreenNameResolver.routeName(for: 42), "Int")
    XCTAssertEqual(ScreenNameResolver.routeName(for: UUID()), "UUID")
  }

  func testRouteNameIgnoresCustomDescriptionOfCaseWithValues() {
    XCTAssertEqual(ScreenNameResolver.routeName(for: DescribedRoute.user(name: "jane")), "user")
  }

  func testSystemFrameworkViewsAreNotScreens() {
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: "MapKit.Map<SwiftUI.EmptyView>"))
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: "_MapKit_SwiftUI.Map"))
    XCTAssertNil(ScreenNameResolver.viewName(fromTypeName: "AVKit.VideoPlayer<SwiftUI.EmptyView>"))
  }
}
