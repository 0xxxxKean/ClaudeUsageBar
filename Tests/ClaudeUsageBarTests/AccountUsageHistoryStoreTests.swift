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

@Test func deleteRemovesOnlyTheTargetedAccount() {
    let url = tempFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = FileAccountUsageHistoryStore(fileURL: url)

    store.upsert(AccountUsageSnapshot(
        accountLabel: "team****@work.com",
        planLabel: "Team",
        sessionPercent: 40,
        weeklyPercent: 55,
        recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
    ))
    store.upsert(AccountUsageSnapshot(
        accountLabel: "pers****@icloud.com",
        planLabel: "Pro",
        sessionPercent: 10,
        weeklyPercent: 20,
        recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
    ))

    store.delete(accountLabel: "team****@work.com")
    let loaded = store.loadAll()

    #expect(loaded.count == 1)
    #expect(loaded.first?.accountLabel == "pers****@icloud.com")
}

@Test func deleteOfUnknownAccountIsANoOp() {
    let url = tempFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = FileAccountUsageHistoryStore(fileURL: url)

    store.upsert(AccountUsageSnapshot(
        accountLabel: "team****@work.com",
        planLabel: "Team",
        sessionPercent: 40,
        weeklyPercent: 55,
        recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
    ))

    store.delete(accountLabel: "nope****@nowhere.com")

    #expect(store.loadAll().count == 1)
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
