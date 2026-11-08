import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // All UI is AppKit-managed (status item + NSPopover) from AppDelegate —
        // MenuBarExtra(.window) centers its content inside a fixed-size window
        // with no way to override that from the content view, which left a
        // blank gap above and below whenever the "other accounts" detail was
        // expanded/collapsed. NSPopover resizes correctly (anchored at the
        // status item, shrinking from the bottom) so this Scene exists only to
        // satisfy App's requirement of having one; it has no visible window.
        Settings {
            EmptyView()
        }
    }
}
