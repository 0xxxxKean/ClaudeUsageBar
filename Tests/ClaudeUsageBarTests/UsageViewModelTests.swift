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

@MainActor
@Test func successfulRefreshProducesLoadedState() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())])
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
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())])
    )

    await viewModel.refresh()

    #expect(viewModel.state == .notLoggedIn)
}

@MainActor
@Test func expiredCredentialProducesTokenExpired() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: false))),
        apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())])
    )

    await viewModel.refresh()

    #expect(viewModel.state == .tokenExpired)
}

@MainActor
@Test func networkFailureWithNoCacheProducesErrorNoCache() async {
    let viewModel = UsageViewModel(
        credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
        apiClient: QueuedUsageAPIClient(results: [.failure(UsageAPIError.httpError(500))])
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
        apiClient: client
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
