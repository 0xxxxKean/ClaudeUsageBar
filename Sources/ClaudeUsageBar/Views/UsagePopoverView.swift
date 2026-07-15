import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.state == .loading)
            }

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("加载中…")
                    .padding(.vertical, 8)
            case .loaded(let snapshot, let fetchedAt):
                content(for: snapshot, footer: "更新于 \(relativeTime(fetchedAt))")
            case .staleWithError(let snapshot, let fetchedAt, let message):
                content(for: snapshot, footer: "\(message) · 上次更新于 \(relativeTime(fetchedAt))")
            case .notLoggedIn:
                Text("未检测到 Claude.ai 订阅登录")
                    .font(.callout)
                Text("请先在终端运行 claude auth login")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .tokenExpired:
                Text("登录已过期")
                    .font(.callout)
                Text("请在终端运行一次 claude 命令刷新后重试")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .errorNoCache(let message):
                Text("获取用量失败")
                    .font(.callout)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 260)
        .task {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func content(for snapshot: UsageSnapshot, footer: String) -> some View {
        Text(snapshot.planLabel)
            .font(.headline)

        usageRow(title: "会话 (5小时)", percent: snapshot.sessionPercent, resetsAt: snapshot.sessionResetsAt)
        usageRow(title: "每周", percent: snapshot.weeklyPercent, resetsAt: snapshot.weeklyResetsAt)

        if let opus = snapshot.opusPercent {
            usageRow(title: "Opus 每周", percent: opus, resetsAt: nil)
        }
        if let sonnet = snapshot.sonnetPercent {
            usageRow(title: "Sonnet 每周", percent: sonnet, resetsAt: nil)
        }

        Text(footer)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func usageRow(title: String, percent: Int, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(percent)%")
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: Double(percent), total: 100)
            if let resetsAt {
                Text("重置于 \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
