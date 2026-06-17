import Foundation

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settingsStore: SettingsStore
    let cursorSessionManager: CursorSessionManager
    let claudeSessionManager: ClaudeSessionManager
    let openAISessionManager: OpenAISessionManager
    let cursorUsageClient: CursorUsageClient
    let claudeUsageClient: ProviderUsageClient
    let openAIUsageClient: ProviderUsageClient
    let cursorUsageCoordinator: CursorUsageCoordinator
    let claudeUsageCoordinator: ClaudeUsageCoordinator
    let openAIUsageCoordinator: OpenAIUsageCoordinator
    let dashboardStore: DashboardStore
    let launchAtLoginController: LaunchAtLoginController

    lazy var settingsWindowController: SettingsWindowController = {
        SettingsWindowController(
            settingsStore: settingsStore,
            dashboardStore: dashboardStore,
            cursorUsageCoordinator: cursorUsageCoordinator,
            claudeUsageCoordinator: claudeUsageCoordinator,
            openAIUsageCoordinator: openAIUsageCoordinator,
            launchAtLoginController: launchAtLoginController
        )
    }()
    lazy var menuBarController: MenuBarController = {
        MenuBarController(
            settingsStore: settingsStore,
            dashboardStore: dashboardStore,
            cursorUsageCoordinator: cursorUsageCoordinator,
            claudeUsageCoordinator: claudeUsageCoordinator,
            openAIUsageCoordinator: openAIUsageCoordinator,
            settingsWindowController: settingsWindowController
        )
    }()

    private init() {
        let settingsStore = SettingsStore()
        let cursorSessionManager = CursorSessionManager()
        let claudeSessionManager = ClaudeSessionManager()
        let openAISessionManager = OpenAISessionManager()
        let cursorUsageClient = CursorDashboardClient(
            settingsStore: settingsStore,
            sessionManager: cursorSessionManager
        )
        let claudeUsageClient = ClaudeDashboardClient(
            settingsStore: settingsStore,
            sessionManager: claudeSessionManager
        )
        let openAIUsageClient = OpenAIDashboardClient(
            settingsStore: settingsStore,
            sessionManager: openAISessionManager
        )
        let cursorUsageCoordinator = CursorUsageCoordinator(
            settingsStore: settingsStore,
            client: cursorUsageClient
        )
        let claudeUsageCoordinator = ClaudeUsageCoordinator(
            settingsStore: settingsStore,
            client: claudeUsageClient
        )
        let openAIUsageCoordinator = OpenAIUsageCoordinator(
            settingsStore: settingsStore,
            client: openAIUsageClient
        )
        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorUsageCoordinator,
            claudeUsageCoordinator: claudeUsageCoordinator,
            openAIUsageCoordinator: openAIUsageCoordinator
        )
        let launchAtLoginController = LaunchAtLoginController()

        self.settingsStore = settingsStore
        self.cursorSessionManager = cursorSessionManager
        self.claudeSessionManager = claudeSessionManager
        self.openAISessionManager = openAISessionManager
        self.cursorUsageClient = cursorUsageClient
        self.claudeUsageClient = claudeUsageClient
        self.openAIUsageClient = openAIUsageClient
        self.cursorUsageCoordinator = cursorUsageCoordinator
        self.claudeUsageCoordinator = claudeUsageCoordinator
        self.openAIUsageCoordinator = openAIUsageCoordinator
        self.dashboardStore = dashboardStore
        self.launchAtLoginController = launchAtLoginController
    }
}
