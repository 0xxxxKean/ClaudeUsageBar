import AppKit
import SwiftUI

/// Owns the status item and its NSPopover directly via AppKit, instead of
/// SwiftUI's `MenuBarExtra`. `MenuBarExtra(.menuBarExtraStyle: .window)`
/// hosts its content inside a privately-managed window that always centers
/// that content vertically — no modifier applied to the content view (not
/// `.fixedSize()`, not a manually driven `NSWindow.setFrame`, not
/// `.frame(alignment: .top)`) can reach outside the view hierarchy to
/// override that. NSPopover, by contrast, anchors at the status item and
/// resizes from the bottom as its content's height changes, which is the
/// behavior this app actually needs when "other accounts" rows expand or
/// collapse.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = UsageViewModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.startAutoRefresh()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let label = NSHostingView(rootView: MenuBarLabelView(viewModel: viewModel))
            label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                label.topAnchor.constraint(equalTo: button.topAnchor),
                label.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item

        let contentController = NSHostingController(rootView: UsagePopoverView(viewModel: viewModel))
        // Keeps `preferredContentSize` in sync with the SwiftUI content's
        // ideal size, which NSPopover observes to resize itself automatically.
        contentController.sizingOptions = [.preferredContentSize]

        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.contentViewController = contentController
        popover = newPopover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
