import AppKit
import SwiftUI

final class SettingsWindowController {
    private let settings: AppSettings
    private let store: ShelfStore
    private var window: NSWindow?

    init(settings: AppSettings, store: ShelfStore) {
        self.settings = settings
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Notch Shelf Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, store: store))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
