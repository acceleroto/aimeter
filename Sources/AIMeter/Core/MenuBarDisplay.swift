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

    static func resolve(
        menuBar: MenuBarAppearanceSettings,
        cursorSnapshot: ProviderUsageSnapshot
    ) -> MenuBarDisplay {
        let settings = menuBar.normalized()
        let titleText = resolvedTitleText(settings: settings, cursorSnapshot: cursorSnapshot)

        return MenuBarDisplay(
            showProgressBarImage: settings.showProgressBar,
            titleText: titleText
        )
    }

    private static func resolvedTitleText(
        settings: MenuBarAppearanceSettings,
        cursorSnapshot: ProviderUsageSnapshot
    ) -> String {
        guard settings.showCursorAutoAPIPercentages else {
            return ""
        }

        if let suffix = cursorAutoAPISuffix(from: cursorSnapshot) {
            return suffix
        }

        if !settings.showProgressBar {
            return placeholderSuffix
        }

        return ""
    }

    private static func cursorAutoAPISuffix(from snapshot: ProviderUsageSnapshot) -> String? {
        guard snapshot.connectionState != .disconnected, snapshot.hasSuccessfulSync else {
            return nil
        }

        return DisplayFormatting.cursorAutoAPISuffix(
            auto: snapshot.autoUsedPercent,
            api: snapshot.apiUsedPercent
        )
    }
}
