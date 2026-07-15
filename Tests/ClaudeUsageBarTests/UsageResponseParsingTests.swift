import Testing
@testable import ClaudeUsageBar

@Test func parsesFiveHourAndSevenDay() throws {
    let json = """
    {
      "five_hour": { "utilization": 63.0, "resets_at": "2026-07-14T16:49:59.546972+00:00" },
      "seven_day": { "utilization": 28.0, "resets_at": "2026-07-20T02:59:59.546990+00:00" },
      "seven_day_opus": null,
      "seven_day_sonnet": null,
      "limits": [],
      "spend": {}
    }
    """.data(using: .utf8)!

    let usage = try parseUsageResponseData(json)

    #expect(usage.fiveHour.utilization == 63.0)
    #expect(usage.sevenDay.utilization == 28.0)
    #expect(usage.sevenDayOpus == nil)
}

@Test func parsesOptionalOpusWindow() throws {
    let json = """
    {
      "five_hour": { "utilization": 10.0, "resets_at": "2026-07-14T16:49:59Z" },
      "seven_day": { "utilization": 5.0, "resets_at": "2026-07-20T02:59:59Z" },
      "seven_day_opus": { "utilization": 42.0, "resets_at": "2026-07-20T02:59:59Z" }
    }
    """.data(using: .utf8)!

    let usage = try parseUsageResponseData(json)

    #expect(usage.sevenDayOpus?.utilization == 42.0)
}

@Test func malformedUsageJSONThrows() {
    let json = "{ \"nope\": true }".data(using: .utf8)!

    #expect(throws: UsageParsingError.invalidJSON) {
        try parseUsageResponseData(json)
    }
}
