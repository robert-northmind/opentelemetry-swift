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
    Row(title: "Push a view controller that stops being tracked") { menu in
      menu.navigationController?.pushViewController(OptOutViewController(), animated: true)
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
    Row(title: "Push a screen that adds a child view controller later") { menu in
      menu.navigationController?.pushViewController(LateChildViewController(), animated: true)
    },
    Row(title: "Push a view controller observed with KVO") { menu in
      menu.navigationController?.pushViewController(ObservedViewController(), animated: true)
    },
    Row(title: "Call viewDidAppear off the main thread (app bug)") { _ in
      callViewDidAppearOffMainThread(DetailViewController(depth: 99))
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
  var screenName: String? {
    "Custom.ScreenName"
  }

  init() {
    super.init(text: "Conforms to ScreenNameProviding and reports \"Custom.ScreenName\".")
    title = "Custom name"
  }
}

final class ExcludedViewController: LabelViewController, ScreenNameProviding {
  var screenName: String? {
    nil
  }

  init() {
    super.init(text: "Returns nil from ScreenNameProviding, so no event is expected.")
    title = "Excluded"
  }
}

/// Tracked at first, then opts out through `ScreenNameProviding` while it is shown. Once it opts
/// out, it is no longer tracked when it appears again, and the screen it covers stays current.
final class OptOutViewController: LabelViewController, ScreenNameProviding {
  private var isExcluded = false

  var screenName: String? {
    isExcluded ? nil : "OptOut.Tracked"
  }

  init() {
    super.init(text: "Reports \"OptOut.Tracked\" until it opts out. "
      + "Stop tracking, push another screen and go back: MenuViewController is expected.")
    title = "Opt out"
    addButton("Stop tracking this screen") { [weak self] in
      self?.isExcluded = true
    }
    addButton("Push another screen") { [weak self] in
      self?.navigationController?.pushViewController(DetailViewController(depth: 1), animated: true)
    }
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

/// A custom container. Its children are app classes too, but they are parts of this screen.
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

/// Adds a child view controller after appearing, like a mini player or a banner. The child is a
/// part of this screen, not a screen of its own.
final class LateChildViewController: LabelViewController {
  init() {
    super.init(text: "Adds a child view controller 0.5 seconds after appearing.")
    title = "Late child"
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard children.isEmpty else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.addMiniPlayer()
    }
  }

  private func addMiniPlayer() {
    let child = ChildViewController(text: "Mini player")
    addChild(child)
    child.view.backgroundColor = .secondarySystemBackground
    child.view.frame = CGRect(x: 0, y: view.bounds.height - 200, width: view.bounds.width, height: 100)
    view.addSubview(child.view)
    child.didMove(toParent: self)
  }
}

/// Observed with key-value observing, which makes the runtime swap in a generated subclass.
final class ObservedViewController: LabelViewController {
  private var observation: NSKeyValueObservation?

  init() {
    super.init(text: "Its title is observed with KVO.")
    title = "Observed"
    observation = observe(\.title) { _, _ in }
  }
}

/// Some apps call appearance methods off the main thread by mistake. The SDK must not crash
/// them for it.
private func callViewDidAppearOffMainThread(_ viewController: UIViewController) {
  nonisolated(unsafe) let viewController = viewController
  let selector = #selector(UIViewController.viewDidAppear(_:))
  typealias Method = @convention(c) (AnyObject, Selector, Bool) -> Void
  let method = unsafeBitCast(viewController.method(for: selector), to: Method.self)
  DispatchQueue.global().async {
    method(viewController, selector, false)
  }
}

/// Replaces the window's root view controller, as apps do when the user signs out.
final class SignedOutViewController: LabelViewController {
  init(restoring root: UIViewController) {
    super.init(text: "Signed out. The window's root view controller was replaced.")
    addButton("Sign in") { [weak self] in
      self?.view.window?.rootViewController = root
    }
  }

  static func signOut() {
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first
    guard let window, let root = window.rootViewController else { return }
    window.rootViewController = SignedOutViewController(restoring: root)
  }
}
