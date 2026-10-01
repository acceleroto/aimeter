import XCTest
@testable import AIMeter

final class ClaudeURLValidatorTests: XCTestCase {
    func testAcceptsKnownClaudeHTTPSHosts() throws {
        let rootURL = try ClaudeURLValidator.validatedUsageURL(from: "https://claude.ai")
        let wwwURL = try ClaudeURLValidator.validatedUsageURL(from: " https://www.claude.ai/settings ")

        XCTAssertEqual(rootURL.host, "claude.ai")
        XCTAssertEqual(wwwURL.host, "www.claude.ai")
    }

    func testRejectsUnsafeOrUnexpectedURLs() {
        let rejectedURLs = [
            "http://claude.ai",
            "file:///Users/divy/private.html",
            "https://claude.ai:8443/settings",
            "https://user:pass@claude.ai/settings",
            "https://api.anthropic.com/usage",
            "https://example.com/settings",
            "http://localhost:3000/settings",
            "claude://settings"
        ]

        for rawURL in rejectedURLs {
            XCTAssertThrowsError(try ClaudeURLValidator.validatedUsageURL(from: rawURL), rawURL)
        }
    }

    func testSanitizesInvalidStoredURLToDefault() {
        XCTAssertEqual(
            ClaudeURLValidator.sanitizedUsageURL("file:///tmp/claude.html"),
            ClaudeSettings.default.usagePageURL
        )
    }

    func testSanitizesRootURLToUsageSettings() {
        XCTAssertEqual(
            ClaudeURLValidator.sanitizedUsageURL("https://claude.ai"),
            "https://claude.ai/settings/usage"
        )
    }

    func testIdentifiesPathAndFragmentUsageSettingsURLs() {
        let usageURLs = [
            "https://claude.ai/settings/usage",
            "https://claude.ai/settings/usage/",
            "https://claude.ai/new#settings/usage",
            "https://claude.ai/new#/settings/usage",
            "https://claude.ai/chat/abc123#settings/usage"
        ]

        for rawURL in usageURLs {
            XCTAssertTrue(ClaudeURLValidator.isUsageSettingsURLString(rawURL), rawURL)
        }

        let nonUsageURLs = [
            "https://claude.ai/new",
            "https://claude.ai/settings/profile",
            "https://claude.ai/new#settings/profile",
            "https://example.com/new#settings/usage"
        ]

        for rawURL in nonUsageURLs {
            XCTAssertFalse(ClaudeURLValidator.isUsageSettingsURLString(rawURL), rawURL)
        }
    }

    func testIdentifiesClaudeAuthenticationFlowURLs() {
        let authFlowURLs = [
            "https://claude.ai/login",
            "https://claude.ai/login/",
            "https://claude.ai/login?from=logout",
            "https://claude.ai/login/code",
            "https://claude.ai/logout",
            "https://claude.ai/magic-link",
            "https://claude.ai/verify",
            "https://claude.ai/verify/email",
            "https://claude.ai/sso-callback",
            "https://claude.ai/oauth/authorize",
            "https://claude.ai/onboarding",
            "https://claude.ai/device-code-verify"
        ]

        for rawURL in authFlowURLs {
            XCTAssertTrue(ClaudeURLValidator.isAuthFlowURLString(rawURL), rawURL)
        }

        let nonAuthFlowURLs = [
            "https://claude.ai",
            "https://claude.ai/new",
            "https://claude.ai/settings/usage",
            "https://claude.ai/chat/abc123"
        ]

        for rawURL in nonAuthFlowURLs {
            XCTAssertFalse(ClaudeURLValidator.isAuthFlowURLString(rawURL), rawURL)
        }
    }
}
