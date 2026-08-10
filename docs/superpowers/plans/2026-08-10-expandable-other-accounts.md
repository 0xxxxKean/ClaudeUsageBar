# Expandable Full-Detail "Other Accounts" Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each cached "other account" snapshot in the popover show full detail (reset times, Opus/Sonnet) matching the live account card, collapsed by default and expandable per-account on tap.

**Architecture:** Extend `AccountUsageSnapshot` with optional reset-time/Opus/Sonnet fields (backward-compatible decode of existing cache files), thread that data through when `UsageViewModel` records history for the live account, then add expand/collapse state and a richer detail view to `UsagePopoverView`'s "other accounts" section.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Testing (`import Testing`, `@Test`), Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-08-10-expandable-other-accounts-design.md`

---

### Task 1: Extend `AccountUsageSnapshot` with full-detail fields

**Files:**
- Modify: `Sources/ClaudeUsageBar/Services/AccountUsageHistoryStore.swift:3-9`
- Create: `Tests/ClaudeUsageBarTests/AccountUsageHistoryStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeUsageBarTests/AccountUsageHistoryStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeUsageBar

private func tempFileURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("account-history-test-\(UUID().uuidString).json")
}

@Test func roundTripsFullSnapshotIncludingNewFields() {
    let url = tempFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = FileAccountUsageHistoryStore(fileURL: url)

    let sessionReset = Date(timeIntervalSince1970: 1_800_000_000)
    let weeklyReset = Date(timeIntervalSince1970: 1_800_500_000)
    let snapshot = AccountUsageSnapshot(
        accountLabel: "team****@work.com",
        planLabel: "Team",
        sessionPercent: 40,
        sessionResetsAt: sessionReset,
        weeklyPercent: 55,
        weeklyResetsAt: weeklyReset,
        opusPercent: 12,
        sonnetPercent: 30,
        recordedAt: Date(timeIntervalSince1970: 1_800_000_500)
    )

    store.upsert(snapshot)
    let loaded = store.loadAll()

    #expect(loaded.count == 1)
    #expect(loaded.first?.sessionResetsAt == sessionReset)
    #expect(loaded.first?.weeklyResetsAt == weeklyReset)
    #expect(loaded.first?.opusPercent == 12)
    #expect(loaded.first?.sonnetPercent == 30)
}

@Test func decodesOldFormatSnapshotMissingNewFieldsAsNil() throws {
    let url = tempFileURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let oldFormatJSON = """
    {
      "team****@work.com": {
        "accountLabel": "team****@work.com",
        "planLabel": "Team",
        "sessionPercent": 40,
        "weeklyPercent": 55,
        "recordedAt": "2026-01-01T00:00:00Z"
      }
    }
    """
    try oldFormatJSON.write(to: url, atomically: true, encoding: .utf8)

    let store = FileAccountUsageHistoryStore(fileURL: url)
    let loaded = store.loadAll()

    #expect(loaded.count == 1)
    #expect(loaded.first?.sessionPercent == 40)
    #expect(loaded.first?.weeklyPercent == 55)
    #expect(loaded.first?.sessionResetsAt == nil)
    #expect(loaded.first?.weeklyResetsAt == nil)
    #expect(loaded.first?.opusPercent == nil)
    #expect(loaded.first?.sonnetPercent == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift test --filter AccountUsageHistoryStoreTests`
Expected: FAIL to compile — `AccountUsageSnapshot` has no members `sessionResetsAt`, `weeklyResetsAt`, `opusPercent`, `sonnetPercent`.

- [ ] **Step 3: Add the new fields**

In `Sources/ClaudeUsageBar/Services/AccountUsageHistoryStore.swift`, replace:

```swift
struct AccountUsageSnapshot: Codable, Equatable {
    let accountLabel: String
    let planLabel: String
    let sessionPercent: Int
    let weeklyPercent: Int
    let recordedAt: Date
}
```

with:

```swift
struct AccountUsageSnapshot: Codable, Equatable {
    let accountLabel: String
    let planLabel: String
    let sessionPercent: Int
    let sessionResetsAt: Date?
    let weeklyPercent: Int
    let weeklyResetsAt: Date?
    let opusPercent: Int?
    let sonnetPercent: Int?
    let recordedAt: Date
}
```

Note: these four new properties are `Optional` with no default, so Swift's synthesized `init(from:)` decodes a missing/absent key as `nil` (built-in behavior for `Optional` stored properties) — this is what makes existing `account-history.json` files on disk decode without a migration step. Existing call sites (in `UsageViewModelTests.swift`) that construct `AccountUsageSnapshot` without the new fields will fail to compile without a default — so also give each new field a default in the declaration:

```swift
struct AccountUsageSnapshot: Codable, Equatable {
    let accountLabel: String
    let planLabel: String
    let sessionPercent: Int
    let sessionResetsAt: Date? = nil
    let weeklyPercent: Int
    let weeklyResetsAt: Date? = nil
    let opusPercent: Int? = nil
    let sonnetPercent: Int? = nil
    let recordedAt: Date
}
```

This keeps the synthesized memberwise initializer usable both with and without the new keyword arguments (Swift lets you omit any parameter that has a default, regardless of its position, as long as the ones you do pass stay in declared order) — the two existing call sites in `UsageViewModelTests.swift` (`successfulRefreshRecordsHistoryForCurrentAccount`'s indirect construction via the view model, and `otherAccountSnapshotsExcludesCurrentAccountAndIncludesPreviouslySeenOnes` / `otherAccountSnapshotsVisibleEvenWhenLoggedOut`, which construct `AccountUsageSnapshot` directly with only the old five fields) keep compiling unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift test --filter AccountUsageHistoryStoreTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Run the full test suite to check nothing else broke**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift test`
Expected: PASS, all existing tests still compile and pass (in particular `UsageViewModelTests.swift`'s direct `AccountUsageSnapshot(...)` constructions).

- [ ] **Step 6: Commit**

```bash
cd "/Users/kean/AI Workspace/ClaudeUsageBar"
git add Sources/ClaudeUsageBar/Services/AccountUsageHistoryStore.swift Tests/ClaudeUsageBarTests/AccountUsageHistoryStoreTests.swift
git commit -m "feat: add reset-time/Opus/Sonnet fields to AccountUsageSnapshot"
```

---

### Task 2: Persist full detail when recording history for the live account

**Files:**
- Modify: `Sources/ClaudeUsageBar/ViewModel/UsageViewModel.swift:131-139`
- Modify: `Tests/ClaudeUsageBarTests/UsageViewModelTests.swift` (add helper + new test)

- [ ] **Step 1: Write the failing test**

In `Tests/ClaudeUsageBarTests/UsageViewModelTests.swift`, add a helper near `makeUsageResponse()` (around line 59-67):

```swift
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
```

Then add a new test after `successfulRefreshRecordsHistoryForCurrentAccount` (around line 254):

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift test --filter successfulRefreshRecordsFullDetailInHistory`
Expected: FAIL — `recorded?.sessionResetsAt` etc. are `nil` because `upsert` currently only passes the old five fields.

- [ ] **Step 3: Pass the full snapshot through to history**

In `Sources/ClaudeUsageBar/ViewModel/UsageViewModel.swift`, replace the `historyStore.upsert` call (lines 131-139):

```swift
        if let accountLabel, case .loaded(let snapshot, let fetchedAt) = state {
            historyStore.upsert(AccountUsageSnapshot(
                accountLabel: accountLabel,
                planLabel: snapshot.planLabel,
                sessionPercent: snapshot.sessionPercent,
                weeklyPercent: snapshot.weeklyPercent,
                recordedAt: fetchedAt
            ))
        }
```

with:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift test --filter successfulRefreshRecordsFullDetailInHistory`
Expected: PASS

- [ ] **Step 5: Run the full test suite**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift test`
Expected: PASS, all tests green.

- [ ] **Step 6: Commit**

```bash
cd "/Users/kean/AI Workspace/ClaudeUsageBar"
git add Sources/ClaudeUsageBar/ViewModel/UsageViewModel.swift Tests/ClaudeUsageBarTests/UsageViewModelTests.swift
git commit -m "feat: persist reset times and Opus/Sonnet in account usage history"
```

---

### Task 3: Expandable detail UI in `UsagePopoverView`

**Files:**
- Modify: `Sources/ClaudeUsageBar/Views/UsagePopoverView.swift:1-95`

This task has no automated tests — the project has no SwiftUI view-level test target, consistent with `UsagePopoverView.swift`'s existing (untested) state today. Verification is a build check (Step 2) plus manual confirmation in Task 4.

- [ ] **Step 1: Add expand/collapse state and rewrite the "other accounts" section**

In `Sources/ClaudeUsageBar/Views/UsagePopoverView.swift`, add the state property right after the `@ObservedObject var viewModel: UsageViewModel` declaration (line 4):

```swift
struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    /// Which cached "other account" cards are expanded, keyed by masked
    /// accountLabel. Per-account, independent — not persisted across
    /// popover recreations.
    @State private var expandedAccounts: Set<String> = []
```

Replace `otherAccountRow(_:)` (lines 75-94) with:

```swift
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
```

`otherAccountExpandedDetail` reuses the existing `usageRow(title:percent:resetsAt:)` helper (already defined at line 147) — the same one the live account card uses — so the expanded "other account" card is visually identical to the live one, including the progress bar and conditional Opus/Sonnet rows.

- [ ] **Step 2: Build to verify it compiles**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Run the full test suite**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && swift test`
Expected: PASS, all tests green (this task adds no new tests but must not break existing ones).

- [ ] **Step 4: Commit**

```bash
cd "/Users/kean/AI Workspace/ClaudeUsageBar"
git add Sources/ClaudeUsageBar/Views/UsagePopoverView.swift
git commit -m "feat: expandable full-detail cards for other accounts"
```

---

### Task 4: Manual verification in the running app

**Files:** none (verification only)

- [ ] **Step 1: Build the app bundle**

Run: `cd "/Users/kean/AI Workspace/ClaudeUsageBar" && ./Scripts/build_app.sh`
Expected: script completes without error and produces/updates the `.app` bundle (check script output for the exact install/output path it prints).

- [ ] **Step 2: Launch and inspect**

Launch the built app (from the path `build_app.sh` reports, or `/Applications` if it installs there), click the menu bar icon to open the popover, and confirm:
- If `account-history.json` already exists at `~/Library/Application Support/ClaudeUsageBar/account-history.json` from prior use, the "其他账号" section still renders without crashing (old-format entries decode with the new fields as absent/omitted).
- Each other-account row is collapsed by default, shows session/weekly % with reset time inline, and no longer shows a relative "last recorded" time.
- Tapping a row expands it in place to show the full card (progress bars, reset times, Opus/Sonnet if present) plus a "上次记录于 …" footer; tapping again collapses it.
- Expanding one account's card does not collapse another already-expanded one (independent toggles).

- [ ] **Step 3: Report results to the user**

Summarize what was checked and any issues found. If everything matches the spec, no further action needed.

---

## Self-Review Notes

- **Spec coverage:** Data model (Task 1), history persistence (Task 2), collapsed-row reset times replacing last-recorded time (Task 3), expanded full card + footer relocation of last-recorded time (Task 3), independent multi-expand (Task 3, `Set<String>` state), backward-compatible decode of old cache (Task 1 test 2) — all covered.
- **No placeholders:** every step has literal code/commands.
- **Type consistency:** `AccountUsageSnapshot` field names (`sessionResetsAt`, `weeklyResetsAt`, `opusPercent`, `sonnetPercent`) used identically across Task 1, 2, and 3. `usageRow(title:percent:resetsAt:)` signature matches its existing definition in `UsagePopoverView.swift:147`.
