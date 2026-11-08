import AppKit
import SwiftUI

/// The status item's icon + optional percent text. Hosted directly inside
/// the NSStatusItem's button via NSHostingView (see AppDelegate).
struct MenuBarLabelView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        switch viewModel.state {
        case .loaded(let snapshot, _):
            content(percent: snapshot.sessionPercent)
        case .staleWithError(let snapshot, _, _):
            content(percent: snapshot.sessionPercent)
        default:
            Image(nsImage: ClaudeMark.image(pointSize: 15, color: NSColor(ClaudeTheme.accent)))
                .frame(width: 15, height: 15)
        }
    }

    private func content(percent: Int) -> some View {
        // Icon always stays Claude's brand terracotta — a stable identity
        // mark — while the percent text still carries the severity color so
        // usage pressure is still visible at a glance.
        let color = ClaudeTheme.severityColor(forPercent: percent)
        return HStack(spacing: 4) {
            Image(nsImage: ClaudeMark.image(pointSize: 15, color: NSColor(ClaudeTheme.accent)))
                .frame(width: 15, height: 15)
            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
