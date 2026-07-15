import Testing
@testable import ClaudeUsageBar

@Test func parsesValidCredentialJSON() throws {
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

    #expect(credential.accessToken == "sk-ant-oat01-test")
    #expect(credential.subscriptionType == "pro")
    #expect(!credential.isExpired)
}

@Test func expiredCredentialReportsExpired() throws {
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

    #expect(credential.isExpired)
}

@Test func malformedJSONThrows() {
    let json = "{ \"not\": \"valid\" }".data(using: .utf8)!

    #expect(throws: CredentialParsingError.invalidJSON) {
        try parseCredentialData(json)
    }
}
