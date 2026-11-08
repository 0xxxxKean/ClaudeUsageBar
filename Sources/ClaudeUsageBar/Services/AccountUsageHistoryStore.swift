import Foundation

struct AccountUsageSnapshot: Codable, Equatable {
    let accountLabel: String
    let planLabel: String
    let sessionPercent: Int
    // `var` (not `let`) is required here: a `let` property with a default
    // value is dropped entirely from Swift's synthesized memberwise init,
    // which would break both old-cache decoding and existing call sites
    // that only pass the original five fields. Not an invitation to mutate.
    var sessionResetsAt: Date? = nil
    let weeklyPercent: Int
    var weeklyResetsAt: Date? = nil
    var opusPercent: Int? = nil
    var sonnetPercent: Int? = nil
    let recordedAt: Date
}

protocol AccountUsageHistoryStore {
    func loadAll() -> [AccountUsageSnapshot]
    func upsert(_ snapshot: AccountUsageSnapshot)
    func delete(accountLabel: String)
}

/// Persists a masked-account → last-known-usage snapshot to a small JSON file.
///
/// `claude auth login` overwrites the single Keychain credential each time you
/// switch Claude.ai accounts on this machine, so there's no way to fetch a
/// live usage number for an account that isn't currently logged in. This store
/// remembers the last snapshot seen *while* each account was active, so the
/// popover can still show "last known" numbers for accounts you've switched
/// away from. Keyed by the already-masked label — the unmasked email is never
/// written to disk.
final class FileAccountUsageHistoryStore: AccountUsageHistoryStore {
    private let fileURL: URL

    init(fileURL: URL = FileAccountUsageHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("ClaudeUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("account-history.json")
    }

    func loadAll() -> [AccountUsageSnapshot] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let dict = try? decoder.decode([String: AccountUsageSnapshot].self, from: data) else { return [] }
        return Array(dict.values)
    }

    func upsert(_ snapshot: AccountUsageSnapshot) {
        var dict = Dictionary(uniqueKeysWithValues: loadAll().map { ($0.accountLabel, $0) })
        dict[snapshot.accountLabel] = snapshot
        write(dict)
    }

    func delete(accountLabel: String) {
        var dict = Dictionary(uniqueKeysWithValues: loadAll().map { ($0.accountLabel, $0) })
        dict.removeValue(forKey: accountLabel)
        write(dict)
    }

    private func write(_ dict: [String: AccountUsageSnapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(dict) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
