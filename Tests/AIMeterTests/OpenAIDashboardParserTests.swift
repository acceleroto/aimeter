import XCTest
@testable import AIMeter

final class OpenAIDashboardParserTests: XCTestCase {
    private let analyticsURL = "https://chatgpt.com/codex/cloud/settings/analytics"

    func testParsesCodexAnalyticsUsageForPlus() {
        let text = """
        Codex
        ChatGPT Plus
        5-hour usage limit
        58% remaining
        Resets in 2 hours
        Weekly usage limit
        85% remaining
        Resets Sunday 11:30 AM
        Credits
        $5.00 remaining
        """

        let result = OpenAIDashboardParser.parseDOMText(text, sourceURL: analyticsURL)

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed OpenAI usage snapshot.")
        }

        XCTAssertEqual(snapshot.provider, .openai)
        XCTAssertEqual(snapshot.planLabel, "ChatGPT Plus")
        XCTAssertEqual(snapshot.primaryMetric.title, "5-hour")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 42, accuracy: 0.01)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Weekly" }?.percent, 15)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Credits" }?.value, "$5.00")
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "5-hour reset" }?.value, "Resets in 2 hours")
        XCTAssertEqual(
            snapshot.secondaryMetrics.first { $0.title == "Weekly reset" }?.value,
            "Resets Sunday 11:30 AM"
        )
        XCTAssertEqual(snapshot.connectionState, .connected)
    }

    func testParsesWeeklyAsPrimaryWhenFiveHourMissing() {
        let text = """
        ChatGPT Plus
        Weekly usage limit
        32% remaining
        Resets in 1 day
        """

        let result = OpenAIDashboardParser.parseDOMText(text, sourceURL: analyticsURL)

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed OpenAI usage snapshot.")
        }

        XCTAssertEqual(snapshot.primaryMetric.title, "Weekly")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 68, accuracy: 0.01)
    }

    func testConvertsBarePercentLinesAsRemainingCapacity() {
        let text = """
        ChatGPT Plus
        5-hour usage limit
        80%
        Weekly usage limit
        90%
        """

        let result = OpenAIDashboardParser.parseDOMText(text, sourceURL: analyticsURL)

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed OpenAI usage snapshot.")
        }

        XCTAssertEqual(snapshot.progressPercent ?? -1, 20, accuracy: 0.01)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Weekly" }?.percent, 10)
    }

    func testDetectsAuthPage() {
        let text = """
        Log in
        Continue with Google
        Sign up for ChatGPT
        """

        let result = OpenAIDashboardParser.parseDOMText(text, sourceURL: "https://chatgpt.com/")

        XCTAssertEqual(result, .authRequired)
    }

    func testParsesJSONResponseBody() {
        let body = """
        {
          "plan": "ChatGPT Plus",
          "five_hour_usage_limit": { "remaining_percent": 45 },
          "weekly_usage_limit": { "remaining_percent": 80 },
          "credits": { "remaining": "$12.50" }
        }
        """

        let result = OpenAIDashboardParser.parseResponseBody(body, sourceURL: analyticsURL)

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed OpenAI JSON usage snapshot.")
        }

        XCTAssertEqual(snapshot.planLabel, "ChatGPT Plus")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 55, accuracy: 0.01)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Weekly" }?.percent, 20)
    }

    func testRejectsNonOpenAIHost() {
        let result = OpenAIDashboardParser.parseResponseBody(
            #"{"usage": 50}"#,
            sourceURL: "https://example.com/usage"
        )

        XCTAssertEqual(result, .noMatch)
    }
}
