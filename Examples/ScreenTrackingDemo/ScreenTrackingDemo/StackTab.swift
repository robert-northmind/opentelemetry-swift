/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI

enum ShopRoute: Hashable {
  case product(id: Int)
  case reviews(productID: Int)
  case cart
}

/// Value-based `NavigationStack` driven by a typed path.
///
/// Layer 3: `.otelTrackNavigation` on the stack names every destination from its route, with no
/// code in the destination views. Expect `ProductList`, `product`, `reviews` and `cart`.
struct StackTab: View {
  @State private var path: [ShopRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section {
          Explanation("NavigationStack(path:) with a typed path. The stack carries "
            + ".otelTrackNavigation, the destinations carry nothing.")
        }
        Section("Value links") {
          ForEach(1 ..< 4) { id in
            NavigationLink("Product \(id)", value: ShopRoute.product(id: id))
          }
        }
        Section("Programmatic") {
          Button("Push product 7, then its reviews") {
            path = [.product(id: 7), .reviews(productID: 7)]
          }
          Button("Push cart") {
            path.append(.cart)
          }
        }
      }
      .navigationTitle("Products")
      .navigationDestination(for: ShopRoute.self) { route in
        destination(for: route)
      }
    }
    .otelTrackNavigation(path: path, rootName: "ProductList")
  }

  @ViewBuilder
  private func destination(for route: ShopRoute) -> some View {
    switch route {
    case let .product(id):
      List {
        NavigationLink("Reviews", value: ShopRoute.reviews(productID: id))
        NavigationLink("Cart", value: ShopRoute.cart)
        Button("Replace with product \(id + 1)") {
          path[path.count - 1] = .product(id: id + 1)
        }
      }
      .navigationTitle("Product \(id)")
    case let .reviews(productID):
      List {
        Text("Reviews for product \(productID)")
        Button("Pop to root") { path.removeAll() }
      }
      .navigationTitle("Reviews")
    case .cart:
      List {
        Text("Cart")
        Button("Pop to root") { path.removeAll() }
      }
      .navigationTitle("Cart")
    }
  }
}
