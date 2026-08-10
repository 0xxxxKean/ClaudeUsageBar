import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    /// Which cached "other account" cards are expanded, keyed by masked
    /// accountLabel. Per-account, independent — not persisted across
    /// popover recreations.
    @State private var expandedAccounts: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("加载中…")
                    .tint(ClaudeTheme.accent)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            case .loaded(let snapshot, let fetchedAt):
                content(for: snapshot, footer: "更新于 \(relativeTime(fetchedAt))")
            case .staleWithError(let snapshot, let fetchedAt, let message):
                content(for: snapshot, footer: "\(message) · 上次更新于 \(relativeTime(fetchedAt))")
            case .notLoggedIn:
                messageBlock(title: "未检测到 Claude.ai 订阅登录", detail: "请先在终端运行 claude auth login")
            case .tokenExpired:
                messageBlock(title: "登录已过期", detail: "请在终端运行一次 claude 命令刷新后重试")
            case .errorNoCache(let message):
                messageBlock(title: "获取用量失败", detail: message)
            }

            if viewModel.accountLabel != nil || viewModel.ipLocationLabel != nil {
                Divider()
                infoFooter
            }

            if !viewModel.otherAccountSnapshots.isEmpty {
                Divider()
                otherAccountsSection
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(ClaudeTheme.surface)
    }

    private var infoFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let accountLabel = viewModel.accountLabel {
                infoRow(label: "账号", value: accountLabel)
            }
            if let ipLocationLabel = viewModel.ipLocationLabel {
                infoRow(label: "IP", value: ipLocationLabel)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
    }

    private var otherAccountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("其他账号 · 上次已知（非实时）")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(viewModel.otherAccountSnapshots, id: \.accountLabel) { snapshot in
                otherAccountRow(snapshot)
            }
        }
    }

    private func otherAccountRow(_ snapshot: AccountUsageSnapshot) -> some View {
        let isExpanded = expandedAccounts.contains(snapshot.accountLabel)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded {
                    expandedAccounts.remove(snapshot.accountLabel)
                } else {
                    expandedAccounts.insert(snapshot.accountLabel)
                }
            } label: {
                otherAccountSummaryRow(snapshot, isExpanded: isExpanded)
            }
            .buttonStyle(.plain)

            if isExpanded {
                otherAccountExpandedDetail(snapshot)
            }
        }
    }

    private func otherAccountSummaryRow(_ snapshot: AccountUsageSnapshot, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(snapshot.accountLabel)
                    .font(.caption)
                Spacer()
                Text(snapshot.planLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(otherAccountSessionSummary(snapshot))
                Text(otherAccountWeeklySummary(snapshot))
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func otherAccountSessionSummary(_ snapshot: AccountUsageSnapshot) -> String {
        guard let resetsAt = snapshot.sessionResetsAt else {
            return "会话 \(snapshot.sessionPercent)%"
        }
        return "会话 \(snapshot.sessionPercent)% · 重置于 \(resetsAt.formatted(date: .omitted, time: .shortened))"
    }

    private func otherAccountWeeklySummary(_ snapshot: AccountUsageSnapshot) -> String {
        guard let resetsAt = snapshot.weeklyResetsAt else {
            return "每周 \(snapshot.weeklyPercent)%"
        }
        return "每周 \(snapshot.weeklyPercent)% · 重置于 \(resetsAt.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private func otherAccountExpandedDetail(_ snapshot: AccountUsageSnapshot) -> some View {
        VStack(spacing: 10) {
            usageRow(title: "会话 (5小时)", percent: snapshot.sessionPercent, resetsAt: snapshot.sessionResetsAt)
            usageRow(title: "每周", percent: snapshot.weeklyPercent, resetsAt: snapshot.weeklyResetsAt)

            if let opus = snapshot.opusPercent {
                usageRow(title: "Opus 每周", percent: opus, resetsAt: nil)
            }
            if let sonnet = snapshot.sonnetPercent {
                usageRow(title: "Sonnet 每周", percent: sonnet, resetsAt: nil)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ClaudeTheme.cardStroke, lineWidth: 1)
                )
        )

        Text("上次记录于 \(relativeTime(snapshot.recordedAt))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ClaudeMarkShape()
                .fill(ClaudeTheme.accent)
                .frame(width: 18, height: 18)
            Text("Claude 用量")
                .font(.system(.headline, design: .rounded))
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(ClaudeTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.state == .loading)
        }
    }

    @ViewBuilder
    private func content(for snapshot: UsageSnapshot, footer: String) -> some View {
        Text(snapshot.planLabel)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(ClaudeTheme.accent)

        VStack(spacing: 10) {
            usageRow(title: "会话 (5小时)", percent: snapshot.sessionPercent, resetsAt: snapshot.sessionResetsAt)
            usageRow(title: "每周", percent: snapshot.weeklyPercent, resetsAt: snapshot.weeklyResetsAt)

            if let opus = snapshot.opusPercent {
                usageRow(title: "Opus 每周", percent: opus, resetsAt: nil)
            }
            if let sonnet = snapshot.sonnetPercent {
                usageRow(title: "Sonnet 每周", percent: sonnet, resetsAt: nil)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ClaudeTheme.cardStroke, lineWidth: 1)
                )
        )

        Text(footer)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func usageRow(title: String, percent: Int, resetsAt: Date?) -> some View {
        let color = ClaudeTheme.severityColor(forPercent: percent)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(percent)%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ClaudeTheme.accentSoft)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                }
            }
            .frame(height: 6)
            if let resetsAt {
                Text("下次重置 \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func messageBlock(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
