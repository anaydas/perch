import AppKit
import SwiftUI

final class SettingsWindowController {
    private let settings: AppSettings
    private let store: ShelfStore
    private let onShowShortcuts: () -> Void
    private var window: NSWindow?

    init(settings: AppSettings, store: ShelfStore, onShowShortcuts: @escaping () -> Void = {}) {
        self.settings = settings
        self.store = store
        self.onShowShortcuts = onShowShortcuts
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 760),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Perch Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: store, onShowShortcuts: onShowShortcuts))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
