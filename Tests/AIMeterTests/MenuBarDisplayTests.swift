import XCTest
@testable import AIMeter

final class MenuBarDisplayTests: XCTestCase {
    func testBarOffWithCursorSyncShowsSuffixOnly() {
        let snapshot = CursorUsageSnapshot(
            planLabel: "Pro",
            totalUsedPercent: 10,
            autoUsedPercent: 5.6,
            apiUsedPercent: 7.8,
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(showProgressBar: false, showCursorAutoAPIPercentages: true),
            cursorSnapshot: snapshot
        )

        XCTAssertFalse(display.showProgressBarImage)
        XCTAssertEqual(display.titleText, "5.6%/7.8%")
        XCTAssertEqual(display.statusItemTitle(includeImage: false), "5.6%/7.8%")
    }

    func testBarOffWithoutCursorSyncShowsPlaceholder() {
        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(showProgressBar: false, showCursorAutoAPIPercentages: true),
            cursorSnapshot: .cursorDisconnected
        )

        XCTAssertFalse(display.showProgressBarImage)
        XCTAssertEqual(display.titleText, MenuBarDisplayResolver.placeholderSuffix)
    }

    func testBarOnWithoutPercentagesShowsImageOnly() {
        let display = MenuBarDisplayResolver.resolve(
            menuBar: .default,
            cursorSnapshot: .cursorDisconnected
        )

        XCTAssertTrue(display.showProgressBarImage)
        XCTAssertTrue(display.titleText.isEmpty)
    }

    func testNormalizedEnablesProgressBarWhenBothFlagsFalse() {
        let settings = MenuBarAppearanceSettings(showProgressBar: false, showCursorAutoAPIPercentages: false)

        XCTAssertTrue(settings.normalized().showProgressBar)
        XCTAssertFalse(settings.normalized().showCursorAutoAPIPercentages)
    }
}
