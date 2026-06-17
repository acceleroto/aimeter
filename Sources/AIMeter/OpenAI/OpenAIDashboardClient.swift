import Foundation

@MainActor
final class OpenAIDashboardClient: ProviderUsageClient {
    let provider = UsageProvider.openai

    private let settingsStore: SettingsStore
    private let sessionManager: OpenAISessionManaging
    private var pendingConnectedSnapshot: ProviderUsageSnapshot?

    init(settingsStore: SettingsStore, sessionManager: OpenAISessionManaging) {
        self.settingsStore = settingsStore
        self.sessionManager = sessionManager
    }

    func connect() async throws {
        let usagePageURL = try resolvedUsagePageURL()
        pendingConnectedSnapshot = try await sessionManager.connect(to: usagePageURL)
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        if let pendingConnectedSnapshot {
            self.pendingConnectedSnapshot = nil
            if pendingConnectedSnapshot.progressPercent != nil {
                return pendingConnectedSnapshot
            }
        }

        let usagePageURL = try resolvedUsagePageURL()
        return try await sessionManager.fetchUsage(from: usagePageURL)
    }

    func disconnect() {
        pendingConnectedSnapshot = nil
        sessionManager.disconnect()
    }

    private func resolvedUsagePageURL() throws -> URL {
        try OpenAIURLValidator.validatedUsageURL(from: settingsStore.settings.openAI.usagePageURL)
    }
}
