import XCTest
@testable import AIMeter

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testInitialSetupCompletionPersistsAcrossReloads() {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let firstStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertFalse(firstStore.settings.hasCompletedInitialSetup)

        firstStore.markInitialSetupComplete()
        XCTAssertTrue(firstStore.settings.hasCompletedInitialSetup)

        let secondStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertTrue(secondStore.settings.hasCompletedInitialSetup)
    }

    func testLegacyCursorSettingsDefaultToIncompleteOnboarding() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let legacyCursorSettings = CursorSettings(usagePageURL: "https://www.cursor.com/settings")
        let encoded = try JSONEncoder().encode(legacyCursorSettings)
        userDefaults.set(encoded, forKey: "aimeter.cursor.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertFalse(store.settings.hasCompletedInitialSetup)
        XCTAssertEqual(store.settings.cursor.usagePageURL, "https://www.cursor.com/settings")
    }

    func testInvalidLegacyCursorURLFallsBackToDefault() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let legacyCursorSettings = CursorSettings(usagePageURL: "file:///tmp/fake-cursor.html")
        let encoded = try JSONEncoder().encode(legacyCursorSettings)
        userDefaults.set(encoded, forKey: "aimeter.cursor.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.settings.cursor.usagePageURL, CursorSettings.default.usagePageURL)
    }

    func testMenuBarAppearanceSettingsPersistAcrossReloads() {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let firstStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertFalse(firstStore.settings.menuBar.showCursorAutoAPIPercentages)
        XCTAssertTrue(firstStore.settings.menuBar.showProgressBar)

        firstStore.settings.menuBar.showCursorAutoAPIPercentages = true

        let secondStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertTrue(secondStore.settings.menuBar.showCursorAutoAPIPercentages)
        XCTAssertTrue(secondStore.settings.menuBar.showProgressBar)
    }

    func testStoredDisabledProgressBarRemainsWhenPercentagesEnabled() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(
            pollIntervalSeconds: 300,
            hasCompletedInitialSetup: false,
            cursor: .default,
            claude: .default,
            menuBar: MenuBarAppearanceSettings(showProgressBar: false, showCursorAutoAPIPercentages: true)
        )
        let encoded = try JSONEncoder().encode(settings)
        userDefaults.set(encoded, forKey: "aimeter.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertFalse(store.settings.menuBar.showProgressBar)
        XCTAssertTrue(store.settings.menuBar.showCursorAutoAPIPercentages)
    }

    func testStoredMenuBarWithNoDisplayOptionsNormalizesToProgressBar() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(
            pollIntervalSeconds: 300,
            hasCompletedInitialSetup: false,
            cursor: .default,
            claude: .default,
            menuBar: MenuBarAppearanceSettings(showProgressBar: false, showCursorAutoAPIPercentages: false)
        )
        let encoded = try JSONEncoder().encode(settings)
        userDefaults.set(encoded, forKey: "aimeter.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertTrue(store.settings.menuBar.showProgressBar)
        XCTAssertFalse(store.settings.menuBar.showCursorAutoAPIPercentages)
    }

    func testDisablingProgressBarEnablesPercentagesWhenNeeded() {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: userDefaults)
        XCTAssertFalse(store.settings.menuBar.showCursorAutoAPIPercentages)

        store.setShowProgressBar(false)

        XCTAssertFalse(store.settings.menuBar.showProgressBar)
        XCTAssertTrue(store.settings.menuBar.showCursorAutoAPIPercentages)
    }

    func testDisablingPercentagesEnablesProgressBarWhenNeeded() {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(userDefaults: userDefaults)
        store.setShowProgressBar(false)
        store.setShowCursorAutoAPIPercentages(true)

        store.setShowCursorAutoAPIPercentages(false)

        XCTAssertTrue(store.settings.menuBar.showProgressBar)
        XCTAssertFalse(store.settings.menuBar.showCursorAutoAPIPercentages)
    }

    func testOpenAICodexPercentagesPersistAcrossReloads() {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let firstStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertFalse(firstStore.settings.menuBar.showOpenAICodexPercentages)

        firstStore.setShowOpenAICodexPercentages(true)

        let secondStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertTrue(secondStore.settings.menuBar.showOpenAICodexPercentages)
    }

    func testExistingSettingsWithoutMenuBarDefaultMenuBarAppearance() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let encoded = try JSONEncoder().encode(
            LegacyAppSettings(
                pollIntervalSeconds: 600,
                hasCompletedInitialSetup: true,
                cursor: CursorSettings(usagePageURL: "https://cursor.com/settings/account")
            )
        )
        userDefaults.set(encoded, forKey: "aimeter.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.settings.menuBar, .default)
    }

    func testExistingSettingsWithoutClaudeKeepCursorConfiguration() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let encoded = try JSONEncoder().encode(
            LegacyAppSettings(
                pollIntervalSeconds: 600,
                hasCompletedInitialSetup: true,
                cursor: CursorSettings(usagePageURL: "https://cursor.com/settings/account")
            )
        )
        userDefaults.set(encoded, forKey: "aimeter.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.settings.pollIntervalSeconds, 600)
        XCTAssertTrue(store.settings.hasCompletedInitialSetup)
        XCTAssertEqual(store.settings.cursor.usagePageURL, "https://cursor.com/settings/account")
        XCTAssertEqual(store.settings.claude, .default)
    }
}

private struct LegacyAppSettings: Codable {
    let pollIntervalSeconds: TimeInterval
    let hasCompletedInitialSetup: Bool
    let cursor: CursorSettings
}
