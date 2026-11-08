import Foundation
import Testing
@testable import ClaudeUsageBar

private struct FakeCredentialStore: CredentialStore {
    let result: Result<OAuthCredential, Error>
    func readCredential() throws -> OAuthCredential {
        try result.get()
    }
}

private final class QueuedUsageAPIClient: UsageAPIClient {
    private var results: [Result<UsageResponse, Error>]
    init(results: [Result<UsageResponse, Error>]) {
        self.results = results
    }
    func fetchUsage(accessToken: String) async throws -> UsageResponse {
        guard !results.isEmpty else {
            throw UsageAPIError.requestFailed("no more queued results")
        }
        return try results.removeFirst().get()
    }
}

private struct StubAccountAPIClient: AccountAPIClient {
    var email: String?
    func fetchAccountEmail(accessToken: String) async throws -> String? { email }
}

private struct StubIPLocationAPIClient: IPLocationAPIClient {
    var result: Result<IPLocationSnapshot, Error> = .failure(IPLocationError.requestFailed)
    func fetchLocation() async throws -> IPLocationSnapshot { try result.get() }
}

private final class InMemoryAccountUsageHistoryStore: AccountUsageHistoryStore {
    private(set) var snapshots: [String: AccountUsageSnapshot] = [:]
    init(seed: [AccountUsageSnapshot] = []) {
        for snapshot in seed { snapshots[snapshot.accountLabel] = snapshot }
    }
    func loadAll() -> [AccountUsageSnapshot] { Array(snapshots.values) }
    func upsert(_ snapshot: AccountUsageSnapshot) { snapshots[snapshot.accountLabel] = snapshot }
    func delete(accountLabel: String) { snapshots.removeValue(forKey: accountLabel) }
}

private func makeCredential(expiresInFuture: Bool) -> OAuthCredential {
    let json = """
    {
      "claudeAiOauth": {
        "accessToken": "sk-ant-oat01-test",
        "refreshToken": "sk-ant-ort01-test",
        "expiresAt": \(expiresInFuture ? "4102444800000" : "1000000000000"),
        "subscriptionType": "pro",
        "rateLimitTier": "default_claude_ai"
      }
    }
    """.data(using: .utf8)!
    return try! parseCredentialData(json)
}

private func makeUsageResponse() -> UsageResponse {
    let json = """
    {
      "five_hour": { "utilization": 63.0, "resets_at": "2026-07-14T16:49:59Z" },
      "seven_day": { "utilization": 28.0, "resets_at": "2026-07-20T02:59:59Z" }
    }
    """.data(using: .utf8)!
    return try! parseUsageResponseData(json)
}

private func makeUsageResponseWithOpusAndSonnet() -> UsageResponse {
    let json = """
    {
      "five_hour": { "utilization": 63.0, "resets_at": "2026-07-14T16:49:59Z" },
      "seven_day": { "utilization": 28.0, "resets_at": "2026-07-20T02:59:59Z" },
      "seven_day_opus": { "utilization": 12.0, "resets_at": "2026-07-20T02:59:59Z" },
      "seven_day_sonnet": { "utilization": 30.0, "resets_at": "2026-07-20T02:59:59Z" }
    }
    """.data(using: .utf8)!
    return try! parseUsageResponseData(json)
}

@MainActor
@Test func successfulRefreshProducesLoadedState() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    guard case .loaded(let snapshot, _) = viewModel.state else {
        Issue.record("Expected .loaded, got \(viewModel.state)")
        return
    }
    #expect(snapshot.sessionPercent == 63)
    #expect(snapshot.weeklyPercent == 28)
    #expect(snapshot.planLabel == "Pro")
}

@MainActor
@Test func missingCredentialProducesNotLoggedIn() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .failure(CredentialStoreError.notFound)),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    #expect(viewModel.state == .notLoggedIn)
}

@MainActor
@Test func expiredCredentialProducesTokenExpired() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: false))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    #expect(viewModel.state == .tokenExpired)
}

@MainActor
@Test func networkFailureWithNoCacheProducesErrorNoCache() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.failure(UsageAPIError.httpError(500))]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    guard case .errorNoCache = viewModel.state else {
        Issue.record("Expected .errorNoCache, got \(viewModel.state)")
        return
    }
}

@MainActor
@Test func networkFailureAfterPriorSuccessFallsBackToStale() async {
    let client = QueuedUsageAPIClient(results: [
        .success(makeUsageResponse()),
        .failure(UsageAPIError.httpError(500))
    ])
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: client,
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()
    await viewModel.refresh()

    guard case .staleWithError(let snapshot, _, let message) = viewModel.state else {
        Issue.record("Expected .staleWithError, got \(viewModel.state)")
        return
    }
    #expect(snapshot.sessionPercent == 63)
    #expect(!message.isEmpty)
}

@MainActor
@Test func successfulRefreshSetsMaskedAccountLabel() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(email: "kean@icloud.com"),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    #expect(viewModel.accountLabel == "kean****@icloud.com")
}

@MainActor
@Test func notLoggedInClearsAccountLabel() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .failure(CredentialStoreError.notFound)),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(email: "kean@icloud.com"),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    #expect(viewModel.accountLabel == nil)
}

@MainActor
@Test func successfulRefreshSetsIPLocationLabel() async {
    let location = IPLocationSnapshot(ip: "1.2.3.4", city: "Phoenix", region: "Arizona", country: "US")
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(result: .success(location)),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    #expect(viewModel.ipLocationLabel == "1.2.3.4 · Phoenix, Arizona, US")
}

@MainActor
@Test func ipLocationLabelSetEvenWhenNotLoggedIn() async {
    let location = IPLocationSnapshot(ip: "1.2.3.4", city: nil, region: nil, country: nil)
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .failure(CredentialStoreError.notFound)),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(result: .success(location)),
        historyStore: InMemoryAccountUsageHistoryStore()
    )

    await viewModel.refresh()

    #expect(viewModel.ipLocationLabel == "1.2.3.4")
}

@Test func maskAccountKeepsFirstFourCharsBeforeAt() {
    #expect(UsageViewModel.maskAccount("kean@icloud.com") == "kean****@icloud.com")
}

@Test func maskAccountHandlesShortLocalPart() {
    #expect(UsageViewModel.maskAccount("ab@x.com") == "ab****@x.com")
}

@Test func maskAccountHandlesNoAtSign() {
    #expect(UsageViewModel.maskAccount("keanchen") == "kean****")
}

@MainActor
@Test func successfulRefreshRecordsHistoryForCurrentAccount() async {
    let historyStore = InMemoryAccountUsageHistoryStore()
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(email: "kean@icloud.com"),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: historyStore
    )

    await viewModel.refresh()

    let recorded = historyStore.loadAll()
    #expect(recorded.count == 1)
    #expect(recorded.first?.accountLabel == "kean****@icloud.com")
    #expect(recorded.first?.sessionPercent == 63)
}

@MainActor
@Test func successfulRefreshRecordsFullDetailInHistory() async {
    let historyStore = InMemoryAccountUsageHistoryStore()
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponseWithOpusAndSonnet())]),
        accountClient: StubAccountAPIClient(email: "kean@icloud.com"),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: historyStore
    )

    await viewModel.refresh()

    let recorded = historyStore.loadAll().first
    #expect(recorded?.sessionResetsAt != nil)
    #expect(recorded?.weeklyResetsAt != nil)
    #expect(recorded?.opusPercent == 12)
    #expect(recorded?.sonnetPercent == 30)
}

@MainActor
@Test func otherAccountSnapshotsExcludesCurrentAccountAndIncludesPreviouslySeenOnes() async {
    let staleSnapshot = AccountUsageSnapshot(
        accountLabel: "team****@work.com",
        planLabel: "Team",
        sessionPercent: 40,
        weeklyPercent: 55,
        recordedAt: Date(timeIntervalSinceNow: -3600)
    )
    let historyStore = InMemoryAccountUsageHistoryStore(seed: [staleSnapshot])
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(email: "kean@icloud.com"),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: historyStore
    )

    await viewModel.refresh()

    #expect(viewModel.otherAccountSnapshots.map(\.accountLabel) == ["team****@work.com"])
}

@MainActor
@Test func deleteHistorySnapshotRemovesFromPublishedListAndStore() async {
    let staleSnapshot = AccountUsageSnapshot(
        accountLabel: "team****@work.com",
        planLabel: "Team",
        sessionPercent: 40,
        weeklyPercent: 55,
        recordedAt: Date(timeIntervalSinceNow: -3600)
    )
    let historyStore = InMemoryAccountUsageHistoryStore(seed: [staleSnapshot])
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .failure(CredentialStoreError.notFound)),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: historyStore
    )
    await viewModel.refresh()
    #expect(viewModel.otherAccountSnapshots.map(\.accountLabel) == ["team****@work.com"])

    viewModel.deleteHistorySnapshot(accountLabel: "team****@work.com")

    #expect(viewModel.otherAccountSnapshots.isEmpty)
    #expect(historyStore.loadAll().isEmpty)
}

@MainActor
@Test func otherAccountSnapshotsVisibleEvenWhenLoggedOut() async {
    let staleSnapshot = AccountUsageSnapshot(
        accountLabel: "team****@work.com",
        planLabel: "Team",
        sessionPercent: 40,
        weeklyPercent: 55,
        recordedAt: Date(timeIntervalSinceNow: -3600)
    )
    let historyStore = InMemoryAccountUsageHistoryStore(seed: [staleSnapshot])
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .failure(CredentialStoreError.notFound)),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())]),
        accountClient: StubAccountAPIClient(),
        ipLocationClient: StubIPLocationAPIClient(),
        historyStore: historyStore
    )

    await viewModel.refresh()

    #expect(viewModel.otherAccountSnapshots.map(\.accountLabel) == ["team****@work.com"])
}
