# ClaudeUsageBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that shows Claude Code subscription usage (5-hour session % and 7-day weekly %) by reading the OAuth token Claude Code already stores in the Keychain and calling `https://api.anthropic.com/api/oauth/usage`, distributed as a `.dmg`.

**Architecture:** Swift Package Manager executable target using SwiftUI's `MenuBarExtra` (macOS 13+). A thin Keychain-reading service and a thin HTTP client feed a `@MainActor` view model that exposes a small state enum; a SwiftUI popover renders that state. A shell script assembles the SPM binary into a `.app` bundle (with `LSUIElement` so it has no Dock icon), ad-hoc signs it, and wraps it in a `.dmg`.

**Tech Stack:** Swift 5 (tools-version 5.9, running on installed Swift 6.1.2 toolchain), SwiftUI, XCTest, macOS Security framework (Keychain), URLSession, `hdiutil`/`codesign` for packaging. No Xcode.app required — Command Line Tools are sufficient.

---

## Reference: Verified API Behavior

Confirmed live on 2026-07-14 against this machine's real Claude Code login:

- Keychain generic-password item, service name `Claude Code-credentials`, holds JSON:
  `{"claudeAiOauth":{"accessToken":"sk-ant-...","refreshToken":"sk-ant-...","expiresAt":<epoch-ms>,"scopes":[...],"subscriptionType":"pro","rateLimitTier":"default_claude_ai"}}`
- `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <accessToken>` returns 200 with:
  `{"five_hour":{"utilization":63.0,"resets_at":"2026-07-14T16:49:59.546972+00:00",...},"seven_day":{"utilization":28.0,"resets_at":"2026-07-20T02:59:59.546990+00:00",...},"seven_day_opus":null,"seven_day_sonnet":null,...}`

All tasks below build against this shape.

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`
- Create: `Tests/ClaudeUsageBarTests/ScaffoldingTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Create the SPM manifest**

`Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeUsageBar",
            path: "Sources/ClaudeUsageBar"
        ),
        .testTarget(
            name: "ClaudeUsageBarTests",
            dependencies: ["ClaudeUsageBar"],
            path: "Tests/ClaudeUsageBarTests"
        )
    ]
)
```

- [ ] **Step 2: Create a placeholder app entry point**

`Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`:
```swift
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
```

- [ ] **Step 3: Create a sanity test**

`Tests/ClaudeUsageBarTests/ScaffoldingTests.swift`:
```swift
import XCTest

final class ScaffoldingTests: XCTestCase {
    func test_packageBuilds() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Create .gitignore**

`.gitignore`:
```
.build/
dist/
.swiftpm/
```

- [ ] **Step 5: Verify build and test**

Run: `cd "/Users/kean/AI workspace/ClaudeUsageBar" && swift build`
Expected: `Build complete!`

Run: `swift test`
Expected: `Test Suite 'All tests' passed` with 1 test run.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "Scaffold ClaudeUsageBar SPM project"
```

---

### Task 2: OAuth Credential Model + Parsing (TDD)

**Files:**
- Create: `Sources/ClaudeUsageBar/Models/OAuthCredential.swift`
- Test: `Tests/ClaudeUsageBarTests/OAuthCredentialParsingTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeUsageBarTests/OAuthCredentialParsingTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageBar

final class OAuthCredentialParsingTests: XCTestCase {
    func test_parsesValidCredentialJSON() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-oat01-test",
            "refreshToken": "sk-ant-ort01-test",
            "expiresAt": 4102444800000,
            "scopes": ["user:inference"],
            "subscriptionType": "pro",
            "rateLimitTier": "default_claude_ai"
          }
        }
        """.data(using: .utf8)!

        let credential = try parseCredentialData(json)

        XCTAssertEqual(credential.accessToken, "sk-ant-oat01-test")
        XCTAssertEqual(credential.subscriptionType, "pro")
        XCTAssertFalse(credential.isExpired)
    }

    func test_expiredCredentialReportsExpired() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-oat01-test",
            "refreshToken": "sk-ant-ort01-test",
            "expiresAt": 1000000000000,
            "subscriptionType": "pro",
            "rateLimitTier": "default_claude_ai"
          }
        }
        """.data(using: .utf8)!

        let credential = try parseCredentialData(json)

        XCTAssertTrue(credential.isExpired)
    }

    func test_malformedJSONThrows() {
        let json = "{ \"not\": \"valid\" }".data(using: .utf8)!

        XCTAssertThrowsError(try parseCredentialData(json)) { error in
            XCTAssertEqual(error as? CredentialParsingError, .invalidJSON)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter OAuthCredentialParsingTests`
Expected: FAIL to build — `cannot find 'parseCredentialData' in scope` (the type/function don't exist yet).

- [ ] **Step 3: Implement the model and parsing function**

`Sources/ClaudeUsageBar/Models/OAuthCredential.swift`:
```swift
import Foundation

struct OAuthCredentialFile: Codable {
    let claudeAiOauth: OAuthCredential
}

struct OAuthCredential: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let subscriptionType: String

    var isExpired: Bool {
        let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
        return expiryDate <= Date()
    }
}

enum CredentialParsingError: Error, Equatable {
    case invalidJSON
}

func parseCredentialData(_ data: Data) throws -> OAuthCredential {
    guard let file = try? JSONDecoder().decode(OAuthCredentialFile.self, from: data) else {
        throw CredentialParsingError.invalidJSON
    }
    return file.claudeAiOauth
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OAuthCredentialParsingTests`
Expected: `Test Suite 'OAuthCredentialParsingTests' passed` with 3 tests run, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsageBar/Models/OAuthCredential.swift Tests/ClaudeUsageBarTests/OAuthCredentialParsingTests.swift
git commit -m "Add OAuthCredential model and JSON parsing"
```

---

### Task 3: Keychain Credential Store

**Files:**
- Create: `Sources/ClaudeUsageBar/Services/KeychainCredentialStore.swift`

No automated test here: `SecItemCopyMatching` is a thin call into the macOS Security framework and reads this machine's real, user-specific Keychain state, which isn't something to fake or fabricate in a unit test. The JSON-parsing logic it delegates to is already covered by Task 2's tests. This component's real behavior against the actual Keychain entry is verified manually in Task 7, Step 4, once the full app can display what it read.

- [ ] **Step 1: Implement the credential store**

`Sources/ClaudeUsageBar/Services/KeychainCredentialStore.swift`:
```swift
import Foundation
import Security

protocol CredentialStore {
    func readCredential() throws -> OAuthCredential
}

enum CredentialStoreError: Error, Equatable {
    case notFound
    case unreadable(OSStatus)
    case parsing(CredentialParsingError)
}

struct KeychainCredentialStore: CredentialStore {
    static let serviceName = "Claude Code-credentials"

    func readCredential() throws -> OAuthCredential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            throw CredentialStoreError.notFound
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialStoreError.unreadable(status)
        }

        do {
            return try parseCredentialData(data)
        } catch let error as CredentialParsingError {
            throw CredentialStoreError.parsing(error)
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeUsageBar/Services/KeychainCredentialStore.swift
git commit -m "Add Keychain-backed credential store"
```

---

### Task 4: Usage Response Model + Parsing (TDD)

**Files:**
- Create: `Sources/ClaudeUsageBar/Models/UsageResponse.swift`
- Test: `Tests/ClaudeUsageBarTests/UsageResponseParsingTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeUsageBarTests/UsageResponseParsingTests.swift`:
```swift
import XCTest
@testable import ClaudeUsageBar

final class UsageResponseParsingTests: XCTestCase {
    func test_parsesFiveHourAndSevenDay() throws {
        let json = """
        {
          "five_hour": { "utilization": 63.0, "resets_at": "2026-07-14T16:49:59.546972+00:00" },
          "seven_day": { "utilization": 28.0, "resets_at": "2026-07-20T02:59:59.546990+00:00" },
          "seven_day_opus": null,
          "seven_day_sonnet": null,
          "limits": [],
          "spend": {}
        }
        """.data(using: .utf8)!

        let usage = try parseUsageResponseData(json)

        XCTAssertEqual(usage.fiveHour.utilization, 63.0)
        XCTAssertEqual(usage.sevenDay.utilization, 28.0)
        XCTAssertNil(usage.sevenDayOpus)
    }

    func test_parsesOptionalOpusWindow() throws {
        let json = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2026-07-14T16:49:59Z" },
          "seven_day": { "utilization": 5.0, "resets_at": "2026-07-20T02:59:59Z" },
          "seven_day_opus": { "utilization": 42.0, "resets_at": "2026-07-20T02:59:59Z" }
        }
        """.data(using: .utf8)!

        let usage = try parseUsageResponseData(json)

        XCTAssertEqual(usage.sevenDayOpus?.utilization, 42.0)
    }

    func test_malformedJSONThrows() {
        let json = "{ \"nope\": true }".data(using: .utf8)!

        XCTAssertThrowsError(try parseUsageResponseData(json)) { error in
            XCTAssertEqual(error as? UsageParsingError, .invalidJSON)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageResponseParsingTests`
Expected: FAIL to build — `cannot find 'parseUsageResponseData' in scope`.

- [ ] **Step 3: Implement the model and parsing function**

`Sources/ClaudeUsageBar/Models/UsageResponse.swift`:
```swift
import Foundation

struct UsageResponse: Codable {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageWindow: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

enum UsageParsingError: Error, Equatable {
    case invalidJSON
}

func parseUsageResponseData(_ data: Data) throws -> UsageResponse {
    guard let response = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
        throw UsageParsingError.invalidJSON
    }
    return response
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageResponseParsingTests`
Expected: `Test Suite 'UsageResponseParsingTests' passed` with 3 tests run, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsageBar/Models/UsageResponse.swift Tests/ClaudeUsageBarTests/UsageResponseParsingTests.swift
git commit -m "Add UsageResponse model and JSON parsing"
```

---

### Task 5: HTTP Usage API Client

**Files:**
- Create: `Sources/ClaudeUsageBar/Services/HTTPUsageAPIClient.swift`

Same rationale as Task 3: this is a thin `URLSession` wrapper around a real network call. Its parsing logic is already covered by Task 4's tests. It's verified live, end-to-end, in Task 7 (we already confirmed the endpoint itself works via `curl` during design).

- [ ] **Step 1: Implement the API client**

`Sources/ClaudeUsageBar/Services/HTTPUsageAPIClient.swift`:
```swift
import Foundation

protocol UsageAPIClient {
    func fetchUsage(accessToken: String) async throws -> UsageResponse
}

enum UsageAPIError: Error, Equatable {
    case requestFailed(String)
    case httpError(Int)
    case parsing(UsageParsingError)
}

struct HTTPUsageAPIClient: UsageAPIClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetchUsage(accessToken: String) async throws -> UsageResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageAPIError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageAPIError.requestFailed("No HTTP response")
        }
        guard httpResponse.statusCode == 200 else {
            throw UsageAPIError.httpError(httpResponse.statusCode)
        }

        do {
            return try parseUsageResponseData(data)
        } catch let error as UsageParsingError {
            throw UsageAPIError.parsing(error)
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeUsageBar/Services/HTTPUsageAPIClient.swift
git commit -m "Add HTTP usage API client"
```

---

### Task 6: Usage View Model State Machine (TDD)

**Files:**
- Create: `Sources/ClaudeUsageBar/ViewModel/UsageViewModel.swift`
- Test: `Tests/ClaudeUsageBarTests/UsageViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeUsageBarTests/UsageViewModelTests.swift`:
```swift
import XCTest
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
final class UsageViewModelTests: XCTestCase {
    func test_successfulRefreshProducesLoadedState() async {
        let viewModel = UsageViewModel(
            credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
            apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())])
        )

        await viewModel.refresh()

        guard case .loaded(let snapshot, _) = viewModel.state else {
            return XCTFail("Expected .loaded, got \(viewModel.state)")
        }
        XCTAssertEqual(snapshot.sessionPercent, 63)
        XCTAssertEqual(snapshot.weeklyPercent, 28)
        XCTAssertEqual(snapshot.planLabel, "Pro")
    }

    func test_missingCredentialProducesNotLoggedIn() async {
        let viewModel = UsageViewModel(
            credentialStore: FakeCredentialStore(result: .failure(CredentialStoreError.notFound)),
            apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())])
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .notLoggedIn)
    }

    func test_expiredCredentialProducesTokenExpired() async {
        let viewModel = UsageViewModel(
            credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: false))),
            apiClient: QueuedUsageAPIClient(results: [.success(makeUsageResponse())])
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.state, .tokenExpired)
    }

    func test_networkFailureWithNoCacheProducesErrorNoCache() async {
        let viewModel = UsageViewModel(
            credentialStore: FakeCredentialStore(result: .success(makeCredential(expiresInFuture: true))),
            apiClient: QueuedUsageAPIClient(results: [.failure(UsageAPIError.httpError(500))])
        )

        await viewModel.refresh()

        guard case .errorNoCache = viewModel.state else {
            return XCTFail("Expected .errorNoCache, got \(viewModel.state)")
        }
    }

    func test_networkFailureAfterPriorSuccessFallsBackToStale() async {
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
            return XCTFail("Expected .staleWithError, got \(viewModel.state)")
        }
        XCTAssertEqual(snapshot.sessionPercent, 63)
        XCTAssertFalse(message.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageViewModelTests`
Expected: FAIL to build — `cannot find 'UsageViewModel' in scope`.

- [ ] **Step 3: Implement the view model**

`Sources/ClaudeUsageBar/ViewModel/UsageViewModel.swift`:
```swift
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

    private let credentialStore: CredentialStore
    private let apiClient: UsageAPIClient
    private var lastSnapshot: (snapshot: UsageSnapshot, fetchedAt: Date)?

    init(credentialStore: CredentialStore = KeychainCredentialStore(),
         apiClient: UsageAPIClient = HTTPUsageAPIClient()) {
        self.credentialStore = credentialStore
        self.apiClient = apiClient
    }

    func refresh() async {
        state = .loading

        let credential: OAuthCredential
        do {
            credential = try credentialStore.readCredential()
        } catch CredentialStoreError.notFound {
            state = .notLoggedIn
            return
        } catch {
            state = fallbackState(message: "读取登录信息失败")
            return
        }

        if credential.isExpired {
            state = .tokenExpired
            return
        }

        do {
            let usage = try await apiClient.fetchUsage(accessToken: credential.accessToken)
            let snapshot = UsageSnapshot(
                planLabel: credential.subscriptionType.capitalized,
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
    }

    private func fallbackState(message: String) -> UsageState {
        if let last = lastSnapshot {
            return .staleWithError(last.snapshot, fetchedAt: last.fetchedAt, message: message)
        }
        return .errorNoCache(message)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageViewModelTests`
Expected: `Test Suite 'UsageViewModelTests' passed` with 5 tests run, 0 failures.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: all tests across all files pass (1 scaffolding + 3 + 3 + 5 = 12 tests, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeUsageBar/ViewModel/UsageViewModel.swift Tests/ClaudeUsageBarTests/UsageViewModelTests.swift
git commit -m "Add UsageViewModel state machine with cached-fallback logic"
```

---

### Task 7: SwiftUI Views, App Wiring, and Manual End-to-End Verification

**Files:**
- Create: `Sources/ClaudeUsageBar/Views/UsagePopoverView.swift`
- Modify: `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift` (replace the Task 1 placeholder)

- [ ] **Step 1: Implement the popover view**

`Sources/ClaudeUsageBar/Views/UsagePopoverView.swift`:
```swift
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
```

- [ ] **Step 2: Replace the placeholder app entry point**

Replace the full contents of `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`:
```swift
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
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Manual verification — real Keychain and network (human step, cannot be automated)**

Run: `swift run ClaudeUsageBar`

This launches the app in the foreground of your terminal; a menu bar icon should appear in the top-right of the screen. Click it and confirm:
- A one-time macOS dialog may appear asking for permission to read the `Claude Code-credentials` Keychain item ("ClaudeUsageBar wants to use your confidential information..."). This is expected — it's macOS protecting a Keychain item owned by a different app (Claude Code). Approve it.
- The popover shows "Pro" as the plan label.
- The session (5小时) percentage roughly matches what you'd see from Claude Code's own usage indicators right now.
- The weekly percentage and both reset times look sane (reset times in the near future, in your local timezone).
- The menu bar icon itself shows a `NN%` label matching the session percentage.

Press Ctrl+C in the terminal to stop the app.

- [ ] **Step 5: Manual verification — network failure fallback (human step)**

With the app already showing a loaded state from Step 4, turn off Wi-Fi, run `swift run ClaudeUsageBar` again, click the icon, and click the refresh button. Confirm the popover shows the previous numbers plus a "网络请求失败 · 上次更新于..." footer instead of going blank. Turn Wi-Fi back on afterward.

Do not test the "not logged in" path by renaming or deleting your real `Claude Code-credentials` Keychain item — that risks breaking your actual Claude Code login. That path is already covered by the `test_missingCredentialProducesNotLoggedIn` unit test in Task 6.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeUsageBar/Views/UsagePopoverView.swift Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift
git commit -m "Wire UsagePopoverView and MenuBarExtra into the app"
```

---

### Task 8: Packaging — .app Bundle and .dmg

**Files:**
- Create: `Scripts/build_app.sh`
- Create: `Scripts/build_dmg.sh`

- [ ] **Step 1: Create the app-bundling script**

`Scripts/build_app.sh`:
```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageBar"
BUILD_DIR=".build/release"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "Building release binary..."
swift build -c release

echo "Assembling ${APP_BUNDLE}..."
rm -rf dist
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.kean.claudeusagebar</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Ad-hoc signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "Done: ${APP_BUNDLE}"
```

- [ ] **Step 2: Create the dmg-packaging script**

`Scripts/build_dmg.sh`:
```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

./Scripts/build_app.sh

DMG_NAME="ClaudeUsageBar.dmg"
STAGING="dist/dmg-staging"

rm -rf "${STAGING}" "dist/${DMG_NAME}"
mkdir -p "${STAGING}"
cp -R "dist/ClaudeUsageBar.app" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

hdiutil create -volname "ClaudeUsageBar" \
  -srcfolder "${STAGING}" \
  -ov -format UDZO \
  "dist/${DMG_NAME}"

echo "Done: dist/${DMG_NAME}"
```

- [ ] **Step 3: Make scripts executable**

Run: `chmod +x Scripts/build_app.sh Scripts/build_dmg.sh`

- [ ] **Step 4: Build and verify the .app bundle**

Run: `./Scripts/build_app.sh`
Expected: ends with `Done: dist/ClaudeUsageBar.app`, no codesign errors.

Run: `open dist/ClaudeUsageBar.app`
Expected: the menu bar icon appears (no Gatekeeper warning yet — locally-built apps you already ran once via `swift run` are typically trusted, or macOS may still prompt; if it does, approve it since this is your own freshly-built binary). Click the icon and confirm the popover renders correctly, same as Task 7 Step 4. Quit via Activity Monitor or `killall ClaudeUsageBar` when done.

- [ ] **Step 5: Build and verify the .dmg**

Run: `./Scripts/build_dmg.sh`
Expected: ends with `Done: dist/ClaudeUsageBar.dmg`.

Run: `open dist/ClaudeUsageBar.dmg`
Expected: a Finder window opens showing `ClaudeUsageBar.app` and an `Applications` shortcut. Drag the app to Applications, eject the mounted volume, then in Finder go to `/Applications`, right-click `ClaudeUsageBar.app` → Open → confirm the Gatekeeper "unidentified developer" dialog appears once, and choosing Open launches the app normally afterward.

- [ ] **Step 6: Commit the packaging scripts**

```bash
git add Scripts/build_app.sh Scripts/build_dmg.sh
git commit -m "Add .app bundling and .dmg packaging scripts"
```

`dist/` stays untracked per `.gitignore` from Task 1 — it's a build artifact, not source.
