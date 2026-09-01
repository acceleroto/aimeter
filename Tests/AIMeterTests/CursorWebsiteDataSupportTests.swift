import XCTest
@testable import AIMeter

final class CursorWebsiteDataSupportTests: XCTestCase {
    func testMatchesCursorWebsiteDataRecords() {
        XCTAssertTrue(CursorWebsiteDataSupport.isCursorWebsiteDataRecord("cursor.com"))
        XCTAssertTrue(CursorWebsiteDataSupport.isCursorWebsiteDataRecord("www.cursor.com"))
        XCTAssertTrue(CursorWebsiteDataSupport.isCursorWebsiteDataRecord("api2.cursor.sh"))
        XCTAssertFalse(CursorWebsiteDataSupport.isCursorWebsiteDataRecord("claude.ai"))
        XCTAssertFalse(CursorWebsiteDataSupport.isCursorWebsiteDataRecord("chatgpt.com"))
    }

    func testMatchesCursorCookieDomains() {
        XCTAssertTrue(CursorWebsiteDataSupport.isCursorCookieDomain("cursor.com"))
        XCTAssertTrue(CursorWebsiteDataSupport.isCursorCookieDomain(".cursor.com"))
        XCTAssertTrue(CursorWebsiteDataSupport.isCursorCookieDomain("api2.cursor.sh"))
        XCTAssertTrue(CursorWebsiteDataSupport.isCursorCookieDomain(".api2.cursor.sh"))
        XCTAssertFalse(CursorWebsiteDataSupport.isCursorCookieDomain("claude.ai"))
        XCTAssertFalse(CursorWebsiteDataSupport.isCursorCookieDomain("notcursor.com"))
    }

    func testDetectsRequestHeaderTooLargePage() {
        let vercelError = """
        This Request has too large of headers.
        494: REQUEST_HEADER_TOO_LARGE
        Code: REQUEST_HEADER_TOO_LARGE
        """

        XCTAssertTrue(CursorWebsiteDataSupport.isRequestHeaderTooLargePage(vercelError))
        XCTAssertFalse(CursorWebsiteDataSupport.isRequestHeaderTooLargePage("Included usage\nTotal 12%"))
    }

    func testRecoveryMessageIsActionable() {
        XCTAssertTrue(
            CursorWebsiteDataSupport.requestHeaderTooLargeRecoveryMessage
                .localizedCaseInsensitiveContains("cleared local Cursor cookies")
        )
    }

    func testLegacyMigrationRunsOnce() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        XCTAssertFalse(userDefaults.bool(forKey: CursorWebsiteDataSupport.legacyDefaultStoreMigrationKey))

        CursorWebsiteDataSupport.migrateLegacyDefaultStoreIfNeeded(userDefaults: userDefaults)
        XCTAssertTrue(userDefaults.bool(forKey: CursorWebsiteDataSupport.legacyDefaultStoreMigrationKey))

        userDefaults.set(false, forKey: CursorWebsiteDataSupport.legacyDefaultStoreMigrationKey)
        CursorWebsiteDataSupport.migrateLegacyDefaultStoreIfNeeded(userDefaults: userDefaults)
        XCTAssertTrue(userDefaults.bool(forKey: CursorWebsiteDataSupport.legacyDefaultStoreMigrationKey))
    }
}
