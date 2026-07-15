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
        } catch CredentialStoreError.unreadable(_) {
            state = fallbackState(message: "无法读取 Keychain 权限，请在弹出的系统对话框中允许访问，然后点击刷新")
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
