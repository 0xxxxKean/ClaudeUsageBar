import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("ClaudeUsageBar scaffold")
        } label: {
            Image(systemName: "gauge.medium")
        }
    }
}
