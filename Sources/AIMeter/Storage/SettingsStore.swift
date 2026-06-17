import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persist()
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "aimeter.settings"
    private let legacyCursorStorageKey = "aimeter.cursor.settings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded.mergedWithDefaults
        } else if
            let data = userDefaults.data(forKey: legacyCursorStorageKey),
            let decoded = try? JSONDecoder().decode(CursorSettings.self, from: data)
        {
            settings = AppSettings(
                pollIntervalSeconds: 300,
                hasCompletedInitialSetup: false,
                cursor: decoded.mergedWithDefaults,
                claude: .default,
                openAI: .default
            )
        } else {
            settings = .default
        }
    }

    func setPollInterval(seconds: TimeInterval) {
        settings.pollIntervalSeconds = max(300, seconds)
    }

    func markInitialSetupComplete() {
        guard !settings.hasCompletedInitialSetup else {
            return
        }

        settings.hasCompletedInitialSetup = true
    }

    func setCursorUsagePageURL(_ url: String) {
        settings.cursor.usagePageURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setClaudeUsagePageURL(_ url: String) {
        settings.claude.usagePageURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setOpenAIUsagePageURL(_ url: String) {
        settings.openAI.usagePageURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setShowProgressBar(_ enabled: Bool) {
        var updated = settings
        var menuBar = updated.menuBar.normalized()

        if !enabled, !menuBar.showCursorAutoAPIPercentages, !menuBar.showOpenAICodexPercentages {
            menuBar.showCursorAutoAPIPercentages = true
        }

        menuBar.showProgressBar = enabled
        updated.menuBar = menuBar.normalized()
        settings = updated
    }

    func setShowCursorAutoAPIPercentages(_ enabled: Bool) {
        var updated = settings
        var menuBar = updated.menuBar.normalized()

        if !enabled, !menuBar.showProgressBar, !menuBar.showOpenAICodexPercentages {
            menuBar.showProgressBar = true
        }

        menuBar.showCursorAutoAPIPercentages = enabled
        updated.menuBar = menuBar.normalized()
        settings = updated
    }

    func setShowOpenAICodexPercentages(_ enabled: Bool) {
        var updated = settings
        var menuBar = updated.menuBar.normalized()

        if !enabled, !menuBar.showProgressBar, !menuBar.showCursorAutoAPIPercentages {
            menuBar.showProgressBar = true
        }

        menuBar.showOpenAICodexPercentages = enabled
        updated.menuBar = menuBar.normalized()
        settings = updated
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(settings) else {
            return
        }

        userDefaults.set(encoded, forKey: storageKey)
    }
}

private extension AppSettings {
    var mergedWithDefaults: AppSettings {
        AppSettings(
            pollIntervalSeconds: max(300, pollIntervalSeconds),
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            cursor: cursor.mergedWithDefaults,
            claude: claude.mergedWithDefaults,
            openAI: openAI.mergedWithDefaults,
            menuBar: menuBar.mergedWithDefaults
        )
    }
}

private extension MenuBarAppearanceSettings {
    var mergedWithDefaults: MenuBarAppearanceSettings {
        normalized()
    }
}

private extension CursorSettings {
    var mergedWithDefaults: CursorSettings {
        CursorSettings(
            usagePageURL: CursorURLValidator.sanitizedUsageURL(usagePageURL)
        )
    }
}

private extension ClaudeSettings {
    var mergedWithDefaults: ClaudeSettings {
        ClaudeSettings(
            usagePageURL: ClaudeURLValidator.sanitizedUsageURL(usagePageURL)
        )
    }
}

private extension OpenAISettings {
    var mergedWithDefaults: OpenAISettings {
        OpenAISettings(
            usagePageURL: OpenAIURLValidator.sanitizedUsageURL(usagePageURL)
        )
    }
}
