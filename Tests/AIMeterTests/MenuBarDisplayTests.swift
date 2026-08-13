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
            cursorSnapshot: snapshot,
            openAISnapshot: .openaiDisconnected
        )

        XCTAssertFalse(display.showProgressBarImage)
        XCTAssertEqual(display.titleText, "6%/8%")
        XCTAssertEqual(display.statusItemTitle(includeImage: false), "6%/8%")
    }

    func testBarOffWithoutCursorSyncShowsPlaceholder() {
        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(showProgressBar: false, showCursorAutoAPIPercentages: true),
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: .openaiDisconnected
        )

        XCTAssertFalse(display.showProgressBarImage)
        XCTAssertEqual(display.titleText, MenuBarDisplayResolver.placeholderSuffix)
    }

    func testBarOffWithoutOpenAISyncShowsWeeklyPlaceholder() {
        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: false,
                showOpenAICodexPercentages: true
            ),
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: .openaiDisconnected
        )

        XCTAssertFalse(display.showProgressBarImage)
        XCTAssertEqual(display.titleText, MenuBarDisplayResolver.openAIPlaceholderSuffix)
    }

    func testBarOnWithoutPercentagesShowsImageOnly() {
        let display = MenuBarDisplayResolver.resolve(
            menuBar: .default,
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: .openaiDisconnected
        )

        XCTAssertTrue(display.showProgressBarImage)
        XCTAssertTrue(display.titleText.isEmpty)
    }

    func testShowsOpenAICodexSuffixOnly() {
        let openAI = ProviderUsageSnapshot(
            provider: .openai,
            planLabel: "ChatGPT Plus",
            primaryMetric: UsageMetric(title: "Weekly", value: "15%", percent: 15),
            secondaryMetrics: [],
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: false,
                showOpenAICodexPercentages: true
            ),
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: openAI
        )

        XCTAssertEqual(display.titleText, "15%")
    }

    func testUsesWeeklyPercentWhenLegacyFiveHourIsPrimary() {
        let openAI = ProviderUsageSnapshot(
            provider: .openai,
            planLabel: "ChatGPT Plus",
            primaryMetric: UsageMetric(title: "5-hour", value: "3%", percent: 3),
            secondaryMetrics: [
                UsageMetric(title: "Weekly", value: "15%", percent: 15)
            ],
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: false,
                showOpenAICodexPercentages: true
            ),
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: openAI
        )

        XCTAssertEqual(display.titleText, "15%")
    }

    func testShowsCursorThenOpenAISegmentsSeparatedByPipe() {
        let cursor = CursorUsageSnapshot(
            planLabel: "Pro",
            totalUsedPercent: 10,
            autoUsedPercent: 8.5,
            apiUsedPercent: 48,
            fetchedAt: Date(),
            connectionState: .connected
        )
        let openAI = ProviderUsageSnapshot(
            provider: .openai,
            planLabel: "ChatGPT Plus",
            primaryMetric: UsageMetric(title: "Weekly", value: "15%", percent: 15),
            secondaryMetrics: [],
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: true,
                showOpenAICodexPercentages: true
            ),
            cursorSnapshot: cursor,
            openAISnapshot: openAI
        )

        XCTAssertEqual(display.titleText, "9%/48% | 15%")
    }

    func testNormalizedEnablesProgressBarWhenAllFlagsFalse() {
        let settings = MenuBarAppearanceSettings(
            showProgressBar: false,
            showCursorAutoAPIPercentages: false,
            showOpenAICodexPercentages: false
        )

        XCTAssertTrue(settings.normalized().showProgressBar)
        XCTAssertFalse(settings.normalized().showCursorAutoAPIPercentages)
        XCTAssertFalse(settings.normalized().showOpenAICodexPercentages)
    }
}
