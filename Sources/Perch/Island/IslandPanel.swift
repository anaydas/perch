import AppKit
import Quartz
import SwiftUI

/// Borderless, non-activating panel that sits over the notch on every Space.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        // Shows over full-screen apps too; full-screen video hides it (IslandController.checkFullScreen).
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        // Clicking the shelf gives it the keyboard (Space for Quick Look, ⌘A, ⌘C, Esc) without
        // activating Perch; the app you were in stays in front.
        becomesKeyOnlyIfNeeded = false
        ignoresMouseEvents = true
    }

    /// Set by the island controller: what Quick Look shows, and what to do when it closes.
    var quickLookSource: QuickLookSource?
    var onQuickLookClosed: () -> Void = {}

    override var canBecomeKey: Bool { true }

    // Quick Look looks for a controller along the responder chain of the key window.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { quickLookSource != nil }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookSource
        panel.delegate = quickLookSource
        panel.level = .statusBar + 1 // above the island
        panel.hidesOnDeactivate = false
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        onQuickLookClosed()
    }
    override var canBecomeMain: Bool { false }

    /// Allow the panel to sit on top of the menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Lets clicks work on the first try even though the panel is never the key window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
