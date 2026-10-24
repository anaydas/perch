import AppKit

/// Menu bar icon with the app's commands (the app has no Dock icon).
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onToggle: () -> Void
    private let onSearch: () -> Void
    private let onPinClipboard: () -> Void
    private let onSettings: () -> Void
    private let onShortcuts: () -> Void
    private let onClearRecent: () -> Void

    init(onToggle: @escaping () -> Void,
         onSearch: @escaping () -> Void,
         onPinClipboard: @escaping () -> Void,
         onSettings: @escaping () -> Void,
         onShortcuts: @escaping () -> Void,
         onClearRecent: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onSearch = onSearch
        self.onPinClipboard = onPinClipboard
        self.onSettings = onSettings
        self.onShortcuts = onShortcuts
        self.onClearRecent = onClearRecent
        super.init()

        item.button?.image = Self.birdIcon()

        let menu = NSMenu()
        menu.addItem(makeItem("Show / Hide Shelf  (⌥Space)", #selector(toggle)))
        menu.addItem(makeItem("Search Shelf  (⌥⌘F)", #selector(search)))
        menu.addItem(makeItem("Pin Clipboard  (⌥⌘V)", #selector(pinClipboard)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Keyboard Shortcuts…", #selector(openShortcuts), key: "/"))
        menu.addItem(makeItem("Clear Recent", #selector(clearRecent)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Perch", #selector(quit), key: "q"))
        item.menu = menu
    }

    /// The app icon's little bird on its perch, as a black-and-white menu bar icon.
    private static func birdIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Same shapes as the app icon (96-point grid), scaled to fit 18 points.
            let t = NSAffineTransform()
            t.scale(by: 18.0 / 58.0)
            t.translateX(by: -19, yBy: -20)
            let shapes = NSBezierPath()
            shapes.append(NSBezierPath(roundedRect: NSRect(x: 18, y: 62, width: 60, height: 10), xRadius: 5, yRadius: 5)) // perch
            shapes.append(NSBezierPath(ovalIn: NSRect(x: 33, y: 34, width: 30, height: 24)))                            // body
            shapes.append(NSBezierPath(ovalIn: NSRect(x: 48, y: 26, width: 18, height: 18)))                            // head
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 35, y: 43))
            tail.curve(to: NSPoint(x: 22, y: 51), controlPoint1: NSPoint(x: 28, y: 40), controlPoint2: NSPoint(x: 24, y: 44))
            tail.curve(to: NSPoint(x: 35, y: 49), controlPoint1: NSPoint(x: 28, y: 52), controlPoint2: NSPoint(x: 32, y: 51))
            tail.close()
            shapes.append(tail)
            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: 64, y: 33))
            beak.line(to: NSPoint(x: 72, y: 35.5))
            beak.line(to: NSPoint(x: 64, y: 38))
            beak.close()
            shapes.append(beak)
            shapes.append(NSBezierPath(rect: NSRect(x: 43, y: 56, width: 3, height: 6)))                                 // legs
            shapes.append(NSBezierPath(rect: NSRect(x: 50, y: 56, width: 3, height: 6)))
            shapes.transform(using: t as AffineTransform)
            NSColor.black.setFill()
            shapes.fill()
            // Eye, cut out so it shows in both light and dark menu bars.
            let eye = NSBezierPath(ovalIn: NSRect(x: 57, y: 31, width: 4, height: 4))
            eye.transform(using: t as AffineTransform)
            NSGraphicsContext.current?.compositingOperation = .clear
            eye.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Perch"
        return image
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func toggle() { onToggle() }
    @objc private func search() { onSearch() }
    @objc private func pinClipboard() { onPinClipboard() }
    @objc private func openSettings() { onSettings() }
    @objc private func openShortcuts() { onShortcuts() }
    @objc private func clearRecent() { onClearRecent() }
    @objc private func quit() { NSApp.terminate(nil) }
}
