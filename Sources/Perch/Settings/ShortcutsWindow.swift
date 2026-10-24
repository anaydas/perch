import AppKit
import SwiftUI

/// Every shortcut in Perch, grouped by where it works. Opened from the menu bar
/// (Keyboard Shortcuts…), Settings, or by pressing ? in the open shelf.
struct ShortcutsView: View {
    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    private struct Group: Identifiable {
        let title: String
        let shortcuts: [Shortcut]
        var id: String { title }
    }

    private let groups: [Group] = [
        Group(title: "Anywhere", shortcuts: [
            Shortcut(keys: "⌥ ⌘ F", action: "Search the shelf"),
            Shortcut(keys: "⌥ ⌘ V", action: "Pin what's on the clipboard"),
            Shortcut(keys: "⌥ Space", action: "Keep the shelf open / let it close"),
        ]),
        Group(title: "In the shelf", shortcuts: [
            Shortcut(keys: "Click", action: "Select a card"),
            Shortcut(keys: "⌘ Click", action: "Add a card to the selection, or remove it"),
            Shortcut(keys: "⇧ Click", action: "Select a range of cards"),
            Shortcut(keys: "Space", action: "Quick Look the selected cards"),
            Shortcut(keys: "⌘ A", action: "Select all"),
            Shortcut(keys: "⌘ C", action: "Copy the selected cards"),
            Shortcut(keys: "Esc", action: "Clear the selection, then close the shelf"),
            Shortcut(keys: "Double-click", action: "Open the item"),
            Shortcut(keys: "Right-click", action: "More: Quick Look, Show in Finder, Fix at the Front, Star, Remove…"),
            Shortcut(keys: "Drag", action: "Drag cards out to use them; drag anything in to pin it"),
            Shortcut(keys: "?", action: "Show this list"),
        ]),
        Group(title: "While searching", shortcuts: [
            Shortcut(keys: "Return", action: "Copy the first match and close the shelf"),
            Shortcut(keys: "Esc", action: "Clear the search, then leave it"),
        ]),
        Group(title: "In Quick Look", shortcuts: [
            Shortcut(keys: "← →", action: "Previous / next selected card"),
            Shortcut(keys: "Space or Esc", action: "Close the preview"),
        ]),
        Group(title: "Anywhere in macOS", shortcuts: [
            Shortcut(keys: "Right-click → Services", action: "Add to Perch: send selected text, images or files"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.shortcuts) { shortcut in
                        HStack(alignment: .firstTextBaseline) {
                            Text(shortcut.keys)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
                                .frame(width: 150, alignment: .leading)
                            Text(shortcut.action)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }
}

final class ShortcutsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Perch Keyboard Shortcuts"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ShortcutsView())
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
