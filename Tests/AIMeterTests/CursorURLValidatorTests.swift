import XCTest
@testable import AIMeter

final class CursorURLValidatorTests: XCTestCase {
    func testAcceptsKnownCursorHTTPSHosts() throws {
        let spendingURL = try CursorURLValidator.validatedUsageURL(
            from: "https://cursor.com/dashboard/spending"
        )
        let settingsURL = try CursorURLValidator.validatedUsageURL(
            from: "https://www.cursor.com/settings"
        )
        let rootURL = try CursorURLValidator.validatedUsageURL(
            from: " https://cursor.com/settings/account "
        )

        XCTAssertEqual(spendingURL.host, "cursor.com")
        XCTAssertEqual(settingsURL.host, "www.cursor.com")
        XCTAssertEqual(rootURL.host, "cursor.com")
    }

    func testAcceptsCursorAPIResponseHost() {
        XCTAssertTrue(
            CursorURLValidator.isAllowedCursorResponseURLString(
                "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
            )
        )
        XCTAssertFalse(
            CursorURLValidator.isAllowedCursorResponseURLString(
                "https://example.com/api/usage"
            )
        )
    }

    func testRejectsUnsafeOrUnexpectedURLs() {
        let rejectedURLs = [
            "http://www.cursor.com/settings",
            "file:///Users/divy/private.html",
            "https://cursor.com:8443/settings",
            "https://user:pass@cursor.com/settings",
            "https://auth.cursor.com/login",
            "https://example.com/settings",
            "http://localhost:3000/settings",
            "cursor://settings"
        ]

        for rawURL in rejectedURLs {
            XCTAssertThrowsError(try CursorURLValidator.validatedUsageURL(from: rawURL), rawURL)
        }
    }

    func testSanitizesInvalidStoredURLToDefault() {
        XCTAssertEqual(
            CursorURLValidator.sanitizedUsageURL("file:///tmp/cursor.html"),
            CursorSettings.default.usagePageURL
        )
    }
}
