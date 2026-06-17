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
            segments.append(cursorSegment(from: cursorSnapshot, showPlaceholderWhenEmpty: !settings.showProgressBar))
        }

        if settings.showOpenAICodexPercentages {
            segments.append(openAISegment(from: openAISnapshot, showPlaceholderWhenEmpty: !settings.showProgressBar))
        }

        return segments.joined(separator: segmentSeparator)
    }

    private static func cursorSegment(
        from snapshot: ProviderUsageSnapshot,
        showPlaceholderWhenEmpty: Bool
    ) -> String {
        if let suffix = cursorAutoAPISuffix(from: snapshot) {
            return suffix
        }

        return showPlaceholderWhenEmpty ? placeholderSuffix : ""
    }

    private static func openAISegment(
        from snapshot: ProviderUsageSnapshot,
        showPlaceholderWhenEmpty: Bool
    ) -> String {
        if let suffix = openAICodexSuffix(from: snapshot) {
            return suffix
        }

        return showPlaceholderWhenEmpty ? placeholderSuffix : ""
    }

    private static func cursorAutoAPISuffix(from snapshot: ProviderUsageSnapshot) -> String? {
        guard snapshot.connectionState != .disconnected, snapshot.hasSuccessfulSync else {
            return nil
        }

        return DisplayFormatting.menuBarCursorAutoAPISuffix(
            auto: snapshot.autoUsedPercent,
            api: snapshot.apiUsedPercent
        )
    }

    private static func openAICodexSuffix(from snapshot: ProviderUsageSnapshot) -> String? {
        guard
            snapshot.provider == .openai,
            snapshot.connectionState != .disconnected,
            snapshot.hasSuccessfulSync,
            let fiveHour = snapshot.progressPercent
        else {
            return nil
        }

        return DisplayFormatting.menuBarOpenAICodexSuffix(
            fiveHour: fiveHour,
            weekly: snapshot.weeklyUsedPercent
        )
    }
}
