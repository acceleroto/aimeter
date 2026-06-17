import XCTest
@testable import AIMeter

final class OpenAIURLValidatorTests: XCTestCase {
    func testAcceptsKnownChatGPTHTTPSHosts() throws {
        let rootURL = try OpenAIURLValidator.validatedUsageURL(from: "https://chatgpt.com")
        let analyticsURL = try OpenAIURLValidator.validatedUsageURL(
            from: " https://www.chatgpt.com/codex/cloud/settings/analytics "
        )

        XCTAssertEqual(rootURL.host, "chatgpt.com")
        XCTAssertEqual(analyticsURL.host, "www.chatgpt.com")
    }

    func testRejectsUnsafeOrUnexpectedURLs() {
        let rejectedURLs = [
            "http://chatgpt.com",
            "file:///Users/divy/private.html",
            "https://chatgpt.com:8443/codex/cloud/settings/analytics",
            "https://user:pass@chatgpt.com/codex/cloud/settings/analytics",
            "https://api.openai.com/v1/usage",
            "https://example.com/codex/cloud/settings/analytics",
            "http://localhost:3000/codex/cloud/settings/analytics",
            "chatgpt://codex/cloud/settings/analytics"
        ]

        for rawURL in rejectedURLs {
            XCTAssertThrowsError(try OpenAIURLValidator.validatedUsageURL(from: rawURL), rawURL)
        }
    }

    func testSanitizesInvalidStoredURLToDefault() {
        XCTAssertEqual(
            OpenAIURLValidator.sanitizedUsageURL("file:///tmp/openai.html"),
            OpenAISettings.default.usagePageURL
        )
    }

    func testSanitizesNonAnalyticsURLToDefault() {
        XCTAssertEqual(
            OpenAIURLValidator.sanitizedUsageURL("https://chatgpt.com/settings"),
            OpenAISettings.default.usagePageURL
        )
    }

    func testDetectsAnalyticsURL() {
        XCTAssertTrue(
            OpenAIURLValidator.isAnalyticsURLString(
                "https://chatgpt.com/codex/cloud/settings/analytics"
            )
        )
        XCTAssertFalse(OpenAIURLValidator.isAnalyticsURLString("https://chatgpt.com/"))
    }
}
