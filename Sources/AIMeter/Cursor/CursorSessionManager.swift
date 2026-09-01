import Foundation
import WebKit

@MainActor
protocol CursorSessionManaging {
    func connect(to usagePageURL: URL) async throws -> CursorUsageSnapshot
    func fetchUsage(from usagePageURL: URL) async throws -> CursorUsageSnapshot
    func disconnect()
}

@MainActor
final class CursorSessionManager: CursorSessionManaging {
    private static let dataStoreIdentifier = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!

    private let dataStore: WKWebsiteDataStore
    private var connectionWindowController: UsageConnectionWindowController?
    private var activeScraper: CursorWebViewScraper?
    private var websiteDataCleanupTask: Task<Void, Never>?

    private(set) var isConnected = false

    init() {
        CursorWebsiteDataSupport.migrateLegacyDefaultStoreIfNeeded()
        self.dataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)
    }

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
    }

    func connect(to usagePageURL: URL) async throws -> CursorUsageSnapshot {
        await waitForWebsiteDataCleanup()

        let scraper = CursorWebViewScraper(mode: .interactive, usagePageURL: usagePageURL, dataStore: dataStore)
        let windowController = UsageConnectionWindowController(title: "Connect Cursor", webView: scraper.webView)

        activeScraper = scraper
        connectionWindowController = windowController
        windowController.onClose = { [weak scraper] in
            scraper?.cancel()
        }
        windowController.show()

        defer {
            activeScraper = nil
            connectionWindowController = nil
        }

        do {
            let snapshot = try await scraper.start()
            isConnected = true
            windowController.close()
            return snapshot
        } catch {
            if windowController.window?.isVisible == true {
                windowController.close()
            }
            throw error
        }
    }

    func fetchUsage(from usagePageURL: URL) async throws -> CursorUsageSnapshot {
        await waitForWebsiteDataCleanup()

        let scraper = CursorWebViewScraper(mode: .background, usagePageURL: usagePageURL, dataStore: dataStore)
        activeScraper = scraper
        defer { activeScraper = nil }
        let snapshot = try await scraper.start()
        isConnected = true
        return snapshot
    }

    func disconnect() {
        isConnected = false
        activeScraper?.cancel()
        connectionWindowController?.close()
        startWebsiteDataCleanup()
    }

    private func startWebsiteDataCleanup() {
        guard websiteDataCleanupTask == nil else {
            return
        }

        websiteDataCleanupTask = Task { [dataStore] in
            await CursorWebsiteDataSupport.clearWebsiteData(in: dataStore)
        }
    }

    private func waitForWebsiteDataCleanup() async {
        guard let websiteDataCleanupTask else {
            return
        }

        await websiteDataCleanupTask.value
        self.websiteDataCleanupTask = nil
    }
}
