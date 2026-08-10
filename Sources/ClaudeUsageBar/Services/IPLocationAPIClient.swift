import Foundation

struct IPLocationSnapshot: Equatable {
    let ip: String
    let city: String?
    let region: String?
    let country: String?

    var summary: String {
        let parts = [city, region, country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? ip : "\(ip) · \(parts.joined(separator: ", "))"
    }
}

protocol IPLocationAPIClient {
    func fetchLocation() async throws -> IPLocationSnapshot
}

enum IPLocationError: Error, Equatable {
    case requestFailed
    case parsing
}

struct HTTPIPLocationAPIClient: IPLocationAPIClient {
    static let endpoint = URL(string: "https://ipinfo.io")!

    private struct RawResponse: Codable {
        let ip: String
        let city: String?
        let region: String?
        let country: String?
    }

    func fetchLocation() async throws -> IPLocationSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IPLocationError.requestFailed
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw IPLocationError.requestFailed
        }
        guard let raw = try? JSONDecoder().decode(RawResponse.self, from: data) else {
            throw IPLocationError.parsing
        }
        return IPLocationSnapshot(ip: raw.ip, city: raw.city, region: raw.region, country: raw.country)
    }
}
