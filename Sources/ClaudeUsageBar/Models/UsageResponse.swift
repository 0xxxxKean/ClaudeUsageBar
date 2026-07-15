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
