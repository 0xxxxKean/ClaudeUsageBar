import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var viewModel = UsageViewModel()

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
            Text("\(snapshot.sessionPercent)%")
        case .staleWithError(let snapshot, _, _):
            Text("\(snapshot.sessionPercent)%")
        default:
            Image(systemName: "gauge.medium")
        }
    }
}
