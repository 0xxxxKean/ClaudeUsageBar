import Foundation

struct UsageSnapshot: Equatable {
    let planLabel: String
    let sessionPercent: Int
    let sessionResetsAt: Date?
    let weeklyPercent: Int
    let weeklyResetsAt: Date?
    let opusPercent: Int?
    let sonnetPercent: Int?
}

enum UsageState: Equatable {
    case idle
    case loading
    case loaded(UsageSnapshot, fetchedAt: Date)
    case staleWithError(UsageSnapshot, fetchedAt: Date, message: String)
    case notLoggedIn
    case tokenExpired
    case errorNoCache(String)
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var state: UsageState = .idle
    /// Masked Claude.ai login email, e.g. "kean****@icloud.com". `nil` while
    /// logged out or if the account endpoint doesn't return one.
    @Published private(set) var accountLabel: String?
    /// "IP · City, Region, Country" summary. Independent of login state.
    @Published private(set) var ipLocationLabel: String?
    /// Last-known usage for accounts previously logged in on this machine
    /// (excludes whichever account is currently active), newest first. Stale
    /// by nature — `claude auth login` overwrites the single Keychain
    /// credential on account switch, so these can't be live-refreshed.
    @Published private(set) var otherAccountSnapshots: [AccountUsageSnapshot] = []

    private let credentialStore: CredentialStore
    private let apiClient: UsageAPIClient
    private let accountClient: AccountAPIClient
    private let ipLocationClient: IPLocationAPIClient
    private let historyStore: AccountUsageHistoryStore
    private var lastSnapshot: (snapshot: UsageSnapshot, fetchedAt: Date)?
    private var refreshTask: Task<Void, Never>?

    init(credentialStore: CredentialStore = KeychainCredentialStore(),
         apiClient: UsageAPIClient = HTTPUsageAPIClient(),
         accountClient: AccountAPIClient = HTTPAccountAPIClient(),
         ipLocationClient: IPLocationAPIClient = HTTPIPLocationAPIClient(),
         historyStore: AccountUsageHistoryStore = FileAccountUsageHistoryStore()) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
        self.accountClient = accountClient
        self.ipLocationClient = ipLocationClient
        self.historyStore = historyStore
    }

    /// Starts a background refresh loop (initial fetch + periodic re-fetch).
    /// Call this once from the app entry point, not from the popover view —
    /// reading the Keychain credential on every popover open is what caused
    /// a macOS authorization prompt each time the menu bar item was clicked.
    func startAutoRefresh(interval: Duration = .seconds(300)) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Fetches usage/account/IP together. IP location is fetched unconditionally
    /// (it needs no credential); account label only once a valid credential is
    /// on hand. Both run concurrently with the usage fetch via `async let` and
    /// are awaited before this returns, so callers (including tests) can rely
    /// on `accountLabel`/`ipLocationLabel` being up to date once `refresh()`
    /// completes — no fire-and-forget background updates.
    func refresh() async {
        state = .loading
        async let ipLocation = fetchIPLocationOrNil()
        await refreshUsageAndAccount()
        ipLocationLabel = await ipLocation?.summary
        otherAccountSnapshots = historyStore.loadAll()
            .filter { $0.accountLabel != accountLabel }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    private func refreshUsageAndAccount() async {
        let credential: OAuthCredential
        do {
            credential = try credentialStore.readCredential()
        } catch CredentialStoreError.notFound {
            state = .notLoggedIn
            accountLabel = nil
            return
        } catch CredentialStoreError.unreadable(_) {
            state = fallbackState(message: "无法读取 Keychain 权限，请在弹出的系统对话框中允许访问，然后点击刷新")
            return
        } catch {
            state = fallbackState(message: "读取登录信息失败")
            return
        }

        if credential.isExpired {
            state = .tokenExpired
            accountLabel = nil
            return
        }

        async let accountEmail = fetchAccountEmailOrNil(accessToken: credential.accessToken)

        do {
            let usage = try await apiClient.fetchUsage(accessToken: credential.accessToken)
            let snapshot = UsageSnapshot(
                planLabel: Self.planLabel(for: credential.subscriptionType),
                sessionPercent: Int(usage.fiveHour.utilization.rounded()),
                sessionResetsAt: parseISODate(usage.fiveHour.resetsAt),
                weeklyPercent: Int(usage.sevenDay.utilization.rounded()),
                weeklyResetsAt: parseISODate(usage.sevenDay.resetsAt),
                opusPercent: usage.sevenDayOpus.map { Int($0.utilization.rounded()) },
                sonnetPercent: usage.sevenDaySonnet.map { Int($0.utilization.rounded()) }
            )
            let now = Date()
            lastSnapshot = (snapshot, now)
            state = .loaded(snapshot, fetchedAt: now)
        } catch {
            state = fallbackState(message: "网络请求失败")
        }

        accountLabel = (await accountEmail).map(Self.maskAccount)

        if let accountLabel, case .loaded(let snapshot, let fetchedAt) = state {
            historyStore.upsert(AccountUsageSnapshot(
                accountLabel: accountLabel,
                planLabel: snapshot.planLabel,
                sessionPercent: snapshot.sessionPercent,
                sessionResetsAt: snapshot.sessionResetsAt,
                weeklyPercent: snapshot.weeklyPercent,
                weeklyResetsAt: snapshot.weeklyResetsAt,
                opusPercent: snapshot.opusPercent,
                sonnetPercent: snapshot.sonnetPercent,
                recordedAt: fetchedAt
            ))
        }
    }

    /// Removes a stale "other account" entry from the history cache. Only
    /// forgets the last-known snapshot kept on this machine — it has no
    /// effect on the real Claude.ai account or any live session.
    func deleteHistorySnapshot(accountLabel: String) {
        historyStore.delete(accountLabel: accountLabel)
        otherAccountSnapshots.removeAll { $0.accountLabel == accountLabel }
    }

    private func fetchIPLocationOrNil() async -> IPLocationSnapshot? {
        try? await ipLocationClient.fetchLocation()
    }

    private func fetchAccountEmailOrNil(accessToken: String) async -> String? {
        (try? await accountClient.fetchAccountEmail(accessToken: accessToken)) ?? nil
    }

    /// Keeps the first 4 characters before "@" (or of the whole string if
    /// there's no "@"), replaces the rest with "****". Pure function, so it's
    /// `nonisolated` — no need to hop onto the main actor to call it.
    nonisolated static func maskAccount(_ raw: String) -> String {
        guard let atIndex = raw.firstIndex(of: "@") else {
            return String(raw.prefix(4)) + "****"
        }
        let localPart = raw[..<atIndex]
        let domain = raw[atIndex...]
        return String(localPart.prefix(4)) + "****" + domain
    }

    private func fallbackState(message: String) -> UsageState {
        if let last = lastSnapshot {
            return .staleWithError(last.snapshot, fetchedAt: last.fetchedAt, message: message)
        }
        return .errorNoCache(message)
    }

    private static func planLabel(for subscriptionType: String) -> String {
        switch subscriptionType.lowercased() {
        case "pro": return "Pro"
        case "max": return "Max"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return subscriptionType.capitalized
        }
    }
}

private func parseISODate(_ string: String?) -> Date? {
    guard let string else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}
