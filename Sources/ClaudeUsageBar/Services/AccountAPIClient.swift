import Foundation

protocol AccountAPIClient {
    func fetchAccountEmail(accessToken: String) async throws -> String?
}

/// Anthropic doesn't publish a documented profile/userinfo endpoint for this
/// OAuth token type, so this tries a couple of plausible candidates (mirroring
/// the already-confirmed `/api/oauth/usage` endpoint's naming) and degrades to
/// `nil` if none of them return a usable email. If neither endpoint works in
/// practice, this is the place to swap in the correct one.
struct HTTPAccountAPIClient: AccountAPIClient {
    static let candidateEndpoints = [
        URL(string: "https://api.anthropic.com/api/oauth/profile")!,
        URL(string: "https://api.anthropic.com/api/oauth/userinfo")!
    ]

    func fetchAccountEmail(accessToken: String) async throws -> String? {
        for endpoint in Self.candidateEndpoints {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                continue
            }
            if let email = Self.extractEmail(from: data) {
                return email
            }
        }
        return nil
    }

    static func extractEmail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let email = json["email"] as? String {
            return email
        }
        if let account = json["account"] as? [String: Any], let email = account["email"] as? String {
            return email
        }
        return nil
    }
}
