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
