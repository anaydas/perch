import AppKit

/// Menu bar icon with the app's commands (the app has no Dock icon).
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onToggle: () -> Void
    private let onPinClipboard: () -> Void
    private let onSettings: () -> Void
    private let onClearRecent: () -> Void

    init(onToggle: @escaping () -> Void,
         onPinClipboard: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onClearRecent: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onPinClipboard = onPinClipboard
        self.onSettings = onSettings
        self.onClearRecent = onClearRecent
        super.init()

        item.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Notch Shelf")

        let menu = NSMenu()
        menu.addItem(makeItem("Show / Hide Shelf  (⌥Space)", #selector(toggle)))
        menu.addItem(makeItem("Pin Clipboard  (⌥⌘V)", #selector(pinClipboard)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Clear Recent", #selector(clearRecent)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Notch Shelf", #selector(quit), key: "q"))
        item.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func toggle() { onToggle() }
    @objc private func pinClipboard() { onPinClipboard() }
    @objc private func openSettings() { onSettings() }
    @objc private func clearRecent() { onClearRecent() }
    @objc private func quit() { NSApp.terminate(nil) }
}
