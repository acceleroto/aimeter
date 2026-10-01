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

    func testShowsClaudeFiveHourAndWeeklySuffixOnly() {
        let claude = ProviderUsageSnapshot(
            provider: .claude,
            planLabel: "Claude Max",
            primaryMetric: UsageMetric(title: "Current session", value: "24%", percent: 24),
            secondaryMetrics: [
                UsageMetric(title: "All models", value: "61%", percent: 61)
            ],
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: false,
                showClaudeUsagePercentages: true
            ),
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: .openaiDisconnected,
            claudeSnapshot: claude
        )

        XCTAssertEqual(display.titleText, "24%/61%")
    }

    func testCountDownClaudePercentagesInvertMenuBarSuffix() {
        let claude = ProviderUsageSnapshot(
            provider: .claude,
            planLabel: "Claude Pro",
            primaryMetric: UsageMetric(title: "Current session", value: "12%", percent: 12),
            secondaryMetrics: [
                UsageMetric(title: "All models", value: "74%", percent: 74)
            ],
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: false,
                showClaudeUsagePercentages: true,
                countDownPercentages: true
            ),
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: .openaiDisconnected,
            claudeSnapshot: claude
        )

        XCTAssertEqual(display.titleText, "88%/26%")
    }

    func testShowsClaudeWeeklyAliasFromSnapshot() {
        let claude = ProviderUsageSnapshot(
            provider: .claude,
            planLabel: "Claude Pro",
            primaryMetric: UsageMetric(title: "Current session", value: "25%", percent: 25),
            secondaryMetrics: [
                UsageMetric(title: "Weekly", value: "32%", percent: 32)
            ],
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: false,
                showClaudeUsagePercentages: true
            ),
            cursorSnapshot: .cursorDisconnected,
            openAISnapshot: .openaiDisconnected,
            claudeSnapshot: claude
        )

        XCTAssertEqual(display.titleText, "25%/32%")
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

    func testCountDownPercentagesInvertMenuBarSuffixes() {
        let cursor = CursorUsageSnapshot(
            planLabel: "Pro",
            totalUsedPercent: 17.4,
            autoUsedPercent: 9,
            apiUsedPercent: 100,
            fetchedAt: Date(),
            connectionState: .connected
        )
        let openAI = ProviderUsageSnapshot(
            provider: .openai,
            planLabel: "ChatGPT Plus",
            primaryMetric: UsageMetric(title: "Weekly", value: "21%", percent: 21),
            secondaryMetrics: [],
            fetchedAt: Date(),
            connectionState: .connected
        )

        let display = MenuBarDisplayResolver.resolve(
            menuBar: MenuBarAppearanceSettings(
                showProgressBar: false,
                showCursorAutoAPIPercentages: true,
                showOpenAICodexPercentages: true,
                countDownPercentages: true
            ),
            cursorSnapshot: cursor,
            openAISnapshot: openAI
        )

        XCTAssertEqual(display.titleText, "91%/0% | 79%")
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
