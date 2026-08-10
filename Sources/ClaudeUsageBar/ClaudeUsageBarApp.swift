import AppKit
import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var viewModel: UsageViewModel

    init() {
        let model = UsageViewModel()
        _viewModel = StateObject(wrappedValue: model)
        model.startAutoRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(viewModel: viewModel)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        switch viewModel.state {
        case .loaded(let snapshot, _):
            menuBarContent(percent: snapshot.sessionPercent)
        case .staleWithError(let snapshot, _, _):
            menuBarContent(percent: snapshot.sessionPercent)
        default:
            Image(nsImage: ClaudeMark.image(pointSize: 15, color: NSColor(ClaudeTheme.accent)))
                .frame(width: 15, height: 15)
        }
    }

    private func menuBarContent(percent: Int) -> some View {
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
