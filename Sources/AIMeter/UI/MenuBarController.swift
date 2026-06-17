import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject {
    private let settingsStore: SettingsStore
    private let dashboardStore: DashboardStore
    private let cursorUsageCoordinator: CursorUsageCoordinator
    private let claudeUsageCoordinator: ClaudeUsageCoordinator
    private let openAIUsageCoordinator: OpenAIUsageCoordinator
    private let settingsWindowController: SettingsWindowController

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refreshAllProviders),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }()

    init(
        settingsStore: SettingsStore,
        dashboardStore: DashboardStore,
        cursorUsageCoordinator: CursorUsageCoordinator,
        claudeUsageCoordinator: ClaudeUsageCoordinator,
        openAIUsageCoordinator: OpenAIUsageCoordinator,
        settingsWindowController: SettingsWindowController
    ) {
        self.settingsStore = settingsStore
        self.dashboardStore = dashboardStore
        self.cursorUsageCoordinator = cursorUsageCoordinator
        self.claudeUsageCoordinator = claudeUsageCoordinator
        self.openAIUsageCoordinator = openAIUsageCoordinator
        self.settingsWindowController = settingsWindowController
        super.init()
    }

    func install() {
        configureStatusItem()
        configurePopover()
        bindDashboard()
        bindSettings()
        updateStatusItem(state: dashboardStore.state, settings: settingsStore.settings)
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "AIMeter.StatusItem"

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = preferredPopoverSize(for: dashboardStore.state)
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                dashboardStore: dashboardStore,
                cursorUsageCoordinator: cursorUsageCoordinator,
                claudeUsageCoordinator: claudeUsageCoordinator,
                openAIUsageCoordinator: openAIUsageCoordinator,
                onRefreshCursor: { [weak cursorUsageCoordinator] in
                    Task { await cursorUsageCoordinator?.refresh() }
                },
                onRefreshClaude: { [weak claudeUsageCoordinator] in
                    Task { await claudeUsageCoordinator?.refresh() }
                },
                onRefreshOpenAI: { [weak openAIUsageCoordinator] in
                    Task { await openAIUsageCoordinator?.refresh() }
                },
                onConnectCursor: { [weak cursorUsageCoordinator] in
                    Task { await cursorUsageCoordinator?.connect() }
                },
                onConnectClaude: { [weak claudeUsageCoordinator] in
                    Task { await claudeUsageCoordinator?.connect() }
                },
                onConnectOpenAI: { [weak openAIUsageCoordinator] in
                    Task { await openAIUsageCoordinator?.connect() }
                },
                onDisconnectCursor: { [weak cursorUsageCoordinator] in
                    cursorUsageCoordinator?.disconnect()
                },
                onDisconnectClaude: { [weak claudeUsageCoordinator] in
                    claudeUsageCoordinator?.disconnect()
                },
                onDisconnectOpenAI: { [weak openAIUsageCoordinator] in
                    openAIUsageCoordinator?.disconnect()
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
    }

    private func bindDashboard() {
        dashboardStore.$state
            .sink { [weak self] state in
                guard let self else { return }
                self.updateStatusItem(state: state, settings: self.settingsStore.settings)
            }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        settingsStore.$settings
            .sink { [weak self] settings in
                guard let self else { return }
                self.updateStatusItem(state: self.dashboardStore.state, settings: settings)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(state: DashboardState, settings: AppSettings) {
        guard let button = statusItem.button else { return }

        popover.contentSize = preferredPopoverSize(for: state)

        let display = MenuBarDisplayResolver.resolve(
            menuBar: settings.menuBar,
            cursorSnapshot: state.cursorSnapshot,
            openAISnapshot: state.openaiSnapshot
        )

        if display.showProgressBarImage {
            button.image = StatusBarImageFactory.image(
                progress: state.menuBarProgressPercent / 100,
                state: primaryConnectionState(for: state)
            )
        } else {
            button.image = nil
        }

        button.attributedTitle = NSAttributedString(string: "")

        if display.hasTitle {
            button.imagePosition = display.showProgressBarImage ? .imageLeading : .noImage
            button.title = display.statusItemTitle(includeImage: display.showProgressBarImage)
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
        }

        button.needsDisplay = true
        statusItem.length = NSStatusItem.variableLength
        button.toolTip = tooltip(for: state, settings: settings)
    }

    private func preferredPopoverSize(for state: DashboardState) -> NSSize {
        let connectedProviderCount = state.connectedProviderSnapshots.count
        let height: CGFloat
        if state.presentationState == .firstRun || connectedProviderCount == 0 {
            height = 420
        } else {
            switch connectedProviderCount {
            case 1:
                height = 370
            case 2:
                height = 560
            default:
                height = 680
            }
        }

        return NSSize(width: 380, height: height)
    }

    private func tooltip(for state: DashboardState, settings: AppSettings) -> String {
        let connectedSnapshots = state.connectedProviderSnapshots
        guard !connectedSnapshots.isEmpty else {
            return "AIMeter: Connect Cursor, Claude, or OpenAI"
        }

        var lines = connectedSnapshots
            .map { snapshot in
                if let progressPercent = snapshot.progressPercent, snapshot.connectionState == .connected {
                    return "\(snapshot.provider.displayName): \(DisplayFormatting.percent(progressPercent)) - \(snapshot.planLabel)"
                }

                return "\(snapshot.provider.displayName): \(snapshot.connectionState.displayText)"
            }

        if settings.menuBar.showCursorAutoAPIPercentages {
            let cursor = state.cursorSnapshot
            if cursor.connectionState != .disconnected, cursor.hasSuccessfulSync {
                lines.append(
                    "Cursor Auto: \(DisplayFormatting.percent(cursor.autoUsedPercent)), API: \(DisplayFormatting.percent(cursor.apiUsedPercent))"
                )
            }
        }

        if settings.menuBar.showOpenAICodexPercentages {
            let openAI = state.openaiSnapshot
            if openAI.connectionState != .disconnected, openAI.hasSuccessfulSync, let fiveHour = openAI.progressPercent {
                lines.append(
                    "OpenAI 5-hour: \(DisplayFormatting.percent(fiveHour)), Weekly: \(DisplayFormatting.percent(openAI.weeklyUsedPercent))"
                )
            }
        }

        return lines.joined(separator: "\n")
    }

    private func primaryConnectionState(for state: DashboardState) -> ProviderConnectionState {
        let snapshots = state.connectedProviderSnapshots

        if snapshots.contains(where: { $0.connectionState == .authExpired }) {
            return .authExpired
        }

        if let syncFailedState = snapshots.compactMap({ snapshot -> ProviderConnectionState? in
            if case .syncFailed = snapshot.connectionState {
                return snapshot.connectionState
            }

            return nil
        }).first {
            return syncFailedState
        }

        if snapshots.contains(where: { $0.connectionState == .connected && $0.progressPercent != nil }) {
            return .connected
        }

        return .disconnected
    }

    @objc
    private func statusItemClicked(_ sender: AnyObject?) {
        if shouldShowContextMenu(for: NSApp.currentEvent) {
            showContextMenu()
            return
        }

        togglePopover(sender)
    }

    @objc
    private func refreshAllProviders() {
        Task {
            await cursorUsageCoordinator.refresh()
            await claudeUsageCoordinator.refresh()
            await openAIUsageCoordinator.refresh()
        }
    }

    @objc
    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func shouldShowContextMenu(for event: NSEvent?) -> Bool {
        guard let event else {
            return false
        }

        if event.type == .rightMouseUp {
            return true
        }

        return event.type == .leftMouseUp && event.modifierFlags.contains(.control)
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }

        let location = NSPoint(x: button.bounds.midX, y: button.bounds.maxY + 2)
        contextMenu.popUp(positioning: nil, at: location, in: button)
    }

    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            installEventMonitors()
        }
    }

    private func openSettings() {
        closePopover(nil)
        settingsWindowController.show()
    }

    private func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        removeEventMonitors()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, self.shouldClosePopover(for: event) {
                    self.closePopover(nil)
                }
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover(nil)
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else {
            return false
        }

        if let popoverWindow = popover.contentViewController?.view.window,
           event.window === popoverWindow {
            return false
        }

        if let statusItemWindow = statusItem.button?.window,
           event.window === statusItemWindow {
            return false
        }

        return true
    }
}

private enum StatusBarImageFactory {
    static func image(progress: Double, state: CursorConnectionState) -> NSImage {
        let size = NSSize(width: 34, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        let barRect = NSRect(x: 4, y: 4, width: 22, height: 8)
        drawBar(rect: barRect, progress: progress, color: .systemBlue, isConnected: state == .connected)
        drawIndicator(atX: 29, state: state)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawBar(rect: NSRect, progress: Double, color: NSColor, isConnected: Bool) {
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.tertiaryLabelColor.withAlphaComponent(isConnected ? 0.25 : 0.12).setFill()
        backgroundPath.fill()

        guard isConnected else {
            return
        }

        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else {
            return
        }

        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * clamped, height: rect.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 4, yRadius: 4)
        color.setFill()
        fillPath.fill()
    }

    private static func drawIndicator(atX x: CGFloat, state: CursorConnectionState) {
        guard state != .connected else { return }

        let indicatorRect = NSRect(x: x, y: 6, width: 4, height: 4)
        let indicatorPath = NSBezierPath(ovalIn: indicatorRect)
        indicatorColor(for: state).setFill()
        indicatorPath.fill()
    }

    private static func indicatorColor(for state: CursorConnectionState) -> NSColor {
        switch state {
        case .authExpired, .syncFailed:
            return .systemOrange
        case .disconnected:
            return .systemYellow
        case .connected:
            return .clear
        }
    }
}
