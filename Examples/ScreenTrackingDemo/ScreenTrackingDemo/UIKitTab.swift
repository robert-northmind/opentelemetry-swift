/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import ScreenInstrumentation
import SwiftUI
import UIKit

/// A UIKit navigation stack embedded in the SwiftUI app.
///
/// Layer 2: view controllers defined by the app are tracked automatically under their class
/// name, with no code in them.
struct UIKitTab: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> UINavigationController {
    UINavigationController(rootViewController: MenuViewController())
  }

  func updateUIViewController(_ viewController: UINavigationController, context: Context) {}
}

final class MenuViewController: UITableViewController {
  private struct Row {
    let title: String
    let action: @MainActor (MenuViewController) -> Void
  }

  private let rows: [Row] = [
    Row(title: "Push a view controller") { menu in
      menu.navigationController?.pushViewController(DetailViewController(depth: 1), animated: true)
    },
    Row(title: "Push a view controller with a custom screen name") { menu in
      menu.navigationController?.pushViewController(CustomNameViewController(), animated: true)
    },
    Row(title: "Push a view controller excluded from tracking") { menu in
      menu.navigationController?.pushViewController(ExcludedViewController(), animated: true)
    },
    Row(title: "Present a page sheet") { menu in
      menu.present(UINavigationController(rootViewController: SheetViewController()), animated: true)
    },
    Row(title: "Present full screen") { menu in
      let controller = UINavigationController(rootViewController: SheetViewController())
      controller.modalPresentationStyle = .fullScreen
      menu.present(controller, animated: true)
    },
    Row(title: "Push a container with two child view controllers") { menu in
      menu.navigationController?.pushViewController(ContainerViewController(), animated: true)
    },
    Row(title: "Push a view controller embedding SwiftUI") { menu in
      menu.navigationController?.pushViewController(EmbeddingViewController(), animated: true)
    },
    Row(title: "Push a plain UIHostingController") { menu in
      let controller = UIHostingController(rootView: HostedSwiftUIView())
      menu.navigationController?.pushViewController(controller, animated: true)
    },
    Row(title: "Push a UIHostingController subclass") { menu in
      menu.navigationController?.pushViewController(HostedSettingsController(), animated: true)
    },
    Row(title: "Show an alert (not a screen)") { menu in
      let alert = UIAlertController(title: "Alert", message: nil, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      menu.present(alert, animated: true)
    }
  ]

  private let cellIdentifier = "cell"

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "UIKit"
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    rows.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
    var content = cell.defaultContentConfiguration()
    content.text = rows[indexPath.row].title
    cell.contentConfiguration = content
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    rows[indexPath.row].action(self)
  }
}

/// Shows a label and optional buttons. Base class for the simple demo screens.
class LabelViewController: UIViewController {
  private let text: String
  private let stack = UIStackView()

  init(text: String) {
    self.text = text
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    stack.axis = .vertical
    stack.spacing = 16
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
    ])
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.textAlignment = .center
    stack.addArrangedSubview(label)
  }

  func addButton(_ title: String, action: @escaping () -> Void) {
    loadViewIfNeeded()
    let button = UIButton(configuration: .bordered(), primaryAction: UIAction(title: title) { _ in action() })
    stack.addArrangedSubview(button)
  }
}

final class DetailViewController: LabelViewController {
  private let depth: Int

  init(depth: Int) {
    self.depth = depth
    super.init(text: "DetailViewController, depth \(depth).\nTracked under its class name.")
    title = "Detail \(depth)"
    addButton("Push another") { [weak self] in
      self?.navigationController?.pushViewController(DetailViewController(depth: depth + 1), animated: true)
    }
    addButton("Pop to root") { [weak self] in
      self?.navigationController?.popToRootViewController(animated: true)
    }
  }
}

final class CustomNameViewController: LabelViewController, ScreenNameProviding {
  var screenName: String? { "Custom.ScreenName" }

  init() {
    super.init(text: "Conforms to ScreenNameProviding and reports \"Custom.ScreenName\".")
    title = "Custom name"
  }
}

final class ExcludedViewController: LabelViewController, ScreenNameProviding {
  var screenName: String? { nil }

  init() {
    super.init(text: "Returns nil from ScreenNameProviding, so no event is expected.")
    title = "Excluded"
  }
}

final class SheetViewController: LabelViewController {
  init() {
    super.init(text: "SheetViewController.\nAfter dismissing, the screen should go back to MenuViewController.")
    title = "Sheet"
    addButton("Push inside the sheet") { [weak self] in
      self?.navigationController?.pushViewController(DetailViewController(depth: 1), animated: true)
    }
    addButton("Dismiss") { [weak self] in
      self?.dismiss(animated: true)
    }
  }
}

/// A custom container. It and both children are app classes, so all three report; the last one
/// to appear wins.
final class ContainerViewController: UIViewController {
  private let top = ChildViewController(text: "Top child")
  private let bottom = ChildViewController(text: "Bottom child")

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Container"
    view.backgroundColor = .systemBackground
    let stack = UIStackView()
    stack.axis = .vertical
    stack.distribution = .fillEqually
    stack.frame = view.bounds
    stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(stack)
    for child in [top, bottom] {
      addChild(child)
      stack.addArrangedSubview(child.view)
      child.didMove(toParent: self)
    }
  }
}

final class ChildViewController: LabelViewController {}

/// A UIKit screen that embeds a SwiftUI view as a child. The embedded hosting controller is a
/// part of this screen and should not be reported as a screen of its own.
final class EmbeddingViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Embedding"
    view.backgroundColor = .systemBackground
    let hosting = UIHostingController(rootView: HostedSwiftUIView())
    addChild(hosting)
    hosting.view.frame = view.bounds
    hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(hosting.view)
    hosting.didMove(toParent: self)
  }
}

struct HostedSwiftUIView: View {
  var body: some View {
    List {
      Explanation("HostedSwiftUIView, shown through a UIHostingController. Pushed directly it "
        + "is only visible to layer 5; embedded in EmbeddingViewController it is not a screen.")
    }
  }
}

/// An app-defined subclass of UIHostingController is an app class, so layer 2 tracks it.
final class HostedSettingsController: UIHostingController<HostedSwiftUIView> {
  init() {
    super.init(rootView: HostedSwiftUIView())
    title = "Hosted settings"
  }

  @available(*, unavailable)
  @MainActor dynamic required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }
}
