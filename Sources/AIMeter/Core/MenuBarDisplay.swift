import Foundation

struct MenuBarDisplay: Equatable {
    let showProgressBarImage: Bool
    let titleText: String

    var hasTitle: Bool {
        !titleText.isEmpty
    }

    func statusItemTitle(includeImage: Bool) -> String {
        guard hasTitle else {
            return ""
        }

        return includeImage ? " \(titleText)" : titleText
    }
}

enum MenuBarDisplayResolver {
    static let placeholderSuffix = "--/--"
    static let openAIPlaceholderSuffix = "--"
    static let segmentSeparator = " | "

    static func resolve(
        menuBar: MenuBarAppearanceSettings,
        cursorSnapshot: ProviderUsageSnapshot,
        openAISnapshot: ProviderUsageSnapshot
    ) -> MenuBarDisplay {
        let settings = menuBar.normalized()
        let titleText = resolvedTitleText(
            settings: settings,
            cursorSnapshot: cursorSnapshot,
            openAISnapshot: openAISnapshot
        )

        return MenuBarDisplay(
            showProgressBarImage: settings.showProgressBar,
            titleText: titleText
        )
    }

    private static func resolvedTitleText(
        settings: MenuBarAppearanceSettings,
        cursorSnapshot: ProviderUsageSnapshot,
        openAISnapshot: ProviderUsageSnapshot
    ) -> String {
        var segments: [String] = []

        if settings.showCursorAutoAPIPercentages {
            segments.append(
                cursorSegment(
                    from: cursorSnapshot,
                    showPlaceholderWhenEmpty: !settings.showProgressBar,
                    countDown: settings.countDownPercentages
                )
            )
        }

        if settings.showOpenAICodexPercentages {
            segments.append(
                openAISegment(
                    from: openAISnapshot,
                    showPlaceholderWhenEmpty: !settings.showProgressBar,
                    countDown: settings.countDownPercentages
                )
            )
        }

        return segments.joined(separator: segmentSeparator)
    }

    private static func cursorSegment(
        from snapshot: ProviderUsageSnapshot,
        showPlaceholderWhenEmpty: Bool,
        countDown: Bool
    ) -> String {
        if let suffix = cursorAutoAPISuffix(from: snapshot, countDown: countDown) {
            return suffix
        }

        return showPlaceholderWhenEmpty ? placeholderSuffix : ""
    }

    private static func openAISegment(
        from snapshot: ProviderUsageSnapshot,
        showPlaceholderWhenEmpty: Bool,
        countDown: Bool
    ) -> String {
        if let suffix = openAICodexSuffix(from: snapshot, countDown: countDown) {
            return suffix
        }

        return showPlaceholderWhenEmpty ? openAIPlaceholderSuffix : ""
    }

    private static func cursorAutoAPISuffix(from snapshot: ProviderUsageSnapshot, countDown: Bool) -> String? {
        guard snapshot.connectionState != .disconnected, snapshot.hasSuccessfulSync else {
            return nil
        }

        return DisplayFormatting.menuBarCursorAutoAPISuffix(
            auto: snapshot.autoUsedPercent,
            api: snapshot.apiUsedPercent,
            countDown: countDown
        )
    }

    private static func openAICodexSuffix(from snapshot: ProviderUsageSnapshot, countDown: Bool) -> String? {
        guard
            snapshot.provider == .openai,
            snapshot.connectionState != .disconnected,
            snapshot.hasSuccessfulSync,
            let weekly = snapshot.weeklyPercent
        else {
            return nil
        }

        return DisplayFormatting.menuBarOpenAICodexSuffix(weekly: weekly, countDown: countDown)
    }
}
