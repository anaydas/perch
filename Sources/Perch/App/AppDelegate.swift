import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) lazy var store = ShelfStore(settings: settings)

    private var island: IslandController?
    private var statusItem: StatusItemController?
    private var clipboard: ClipboardWatcher?
    private var screenshots: ScreenshotWatcher?
    private lazy var claudeSessions = ClaudeSessionWatcher(settings: settings)
    private lazy var claudeUsage = ClaudeUsageWatcher(settings: settings)
    private let hotKeys = HotKeyCenter()
    private lazy var settingsWindow = SettingsWindowController(settings: settings, store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        claudeSessions.start()
        claudeUsage.start()
        let island = IslandController(store: store, settings: settings,
                                      claudeSessions: claudeSessions, claudeUsage: claudeUsage)
        island.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        self.island = island

        statusItem = StatusItemController(
            onToggle: { [weak self] in self?.island?.togglePinned() },
            onPinClipboard: { [weak self] in self?.store.pinCurrentClipboard() },
            onSettings: { [weak self] in self?.settingsWindow.show() },
            onClearRecent: { [weak self] in self?.store.clearRecent() }
        )

        let clipboard = ClipboardWatcher(store: store, settings: settings)
        clipboard.start()
        self.clipboard = clipboard

        let screenshots = ScreenshotWatcher(store: store, settings: settings)
        screenshots.start()
        self.screenshots = screenshots

        // ⌥Space: keep the island open / close it
        hotKeys.register(keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            self?.island?.togglePinned()
        }
        // ⌥⌘V: pin whatever is on the clipboard
        hotKeys.register(keyCode: kVK_ANSI_V, modifiers: optionKey | cmdKey) { [weak self] in
            self?.store.pinCurrentClipboard()
        }
    }
}
