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
