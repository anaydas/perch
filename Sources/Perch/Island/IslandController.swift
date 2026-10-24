import AppKit
import Combine
import IOKit.pwr_mgt
import Quartz
import SwiftUI

/// Places the island on the chosen screen edge and decides when it expands or collapses.
final class IslandController {
    let model = IslandViewModel()
    var onOpenSettings: (() -> Void)?
    var onShowShortcuts: (() -> Void)?

    private let store: ShelfStore
    private let settings: AppSettings
    private let panel: IslandPanel
    private var screen: NSScreen?
    private var trackingTimer: Timer?
    private var leftAt: Date?
    private var enteredAt: Date?
    private var clickMonitor: Any?
    private var wheelMonitor: Any?
    private var pressMonitor: Any?
    /// A mouse press began on the island: don't treat it as a file drag, and don't
    /// hide or move the island until it's released (it may be dragged to a new spot).
    private var pressStartedOnIsland = false
    /// Hidden because a full-screen app or video is in front.
    private var hiddenForFullScreen = false
    private var fullScreenTimer: Timer?
    private var pressMoved = false
    private var keyMonitor: Any?
    private let quickLookSource = QuickLookSource()
    private let multiDragSource = MultiDragSource()
    /// Where a press on the island began, and on which card (for multi-drag).
    private var pressPoint: NSPoint = .zero
    private var pressItemID: UUID?
    private var multiDragStarted = false
    /// Whether the shelf was pinned before search pinned it open.
    private var pinnedBeforeSearch = false
    /// The app that was in front before Quick Look opened (handed the keyboard back afterwards).
    private var appBeforeQuickLook: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()

    init(store: ShelfStore, settings: AppSettings, claudeSessions: ClaudeSessionWatcher, claudeUsage: ClaudeUsageWatcher) {
        self.store = store
        self.settings = settings
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandMetrics.panelSize))

        let actions = IslandActions(
            togglePin: { [weak self] in self?.togglePinned() },
            openSettings: { [weak self] in self?.onOpenSettings?() },
            moveFloating: { [weak self] offset in self?.moveFloating(by: offset) },
            quickLook: { [weak self] in self?.toggleQuickLook() },
            startSearch: { [weak self] in self?.startSearch() },
            endSearch: { [weak self] in self?.endSearch() },
            dismiss: { [weak self] in
                self?.model.isPinned = false
                self?.collapse()
            }
        )
        let root = IslandView(model: model, store: store, settings: settings,
                              claudeSessions: claudeSessions, claudeUsage: claudeUsage, actions: actions)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: IslandMetrics.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        positionPanel()
        panel.orderFrontRegardless()

        // Full-screen video (Netflix, YouTube, TV, VLC…): hide while it plays.
        fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkFullScreen()
        }
        settings.$hideInFullScreen
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.checkFullScreen() }
            .store(in: &cancellables)

        // Poll the cursor: cheap, and it also works while dragging files from other apps.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.trackCursor()
        }

        // Clicks in other apps (or the desktop) close the island, even when it's pinned open.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.clickedOutside()
        }

        // A plain mouse wheel only scrolls vertically; turn that into sideways scrolling for the
        // card row (top/bottom). The side panel's grid scrolls vertically, so leave it alone there.
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel, !self.model.layout.isVertical else { return event }
            return Self.horizontalScroll(from: event) ?? event
        }

        panel.quickLookSource = quickLookSource
        panel.onQuickLookClosed = { [weak self] in
            self?.appBeforeQuickLook?.activate()
            self?.appBeforeQuickLook = nil
        }
        multiDragSource.onEnd = { [weak store] in store?.isDraggingOut = false }

        // Presses on the island: a click opens it, a drag (floating style) moves it, and dragging
        // one of several selected cards drags them all.
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch event.type {
            case .leftMouseDown:
                self.pressStartedOnIsland = true
                self.pressMoved = false
                self.multiDragStarted = false
                self.pressPoint = event.locationInWindow
                self.pressItemID = self.model.hoveredItemID
                if self.model.isExpanded {
                    // Take the keyboard (Esc, Space, ⌘A, ⌘C) without bringing Perch to the front.
                    if !self.panel.isKeyWindow { self.panel.makeKey() }
                    // A plain click anywhere that isn't a card clears the selection.
                    let modifiers = event.modifierFlags.intersection([.command, .shift])
                    if self.pressItemID == nil && modifiers.isEmpty && !self.model.selection.isEmpty {
                        self.model.selection = []
                    }
                }
            case .leftMouseDragged:
                self.pressMoved = true
                if self.handleMultiDrag(event) { return nil }
            default:
                if self.pressStartedOnIsland && !self.pressMoved && !self.model.isExpanded { self.expand() }
                self.pressStartedOnIsland = false
            }
            return event
        }

        // Keys while the shelf has the keyboard: Space = Quick Look, ⌘A = select all,
        // ⌘C = copy selection, Esc = clear selection.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.model.isExpanded,
                  !(self.panel.firstResponder is NSText) else { return event } // typing in a text field
            let command = event.modifierFlags.contains(.command)
            switch (event.keyCode, command) {
            case (49, false): self.toggleQuickLook(); return nil                     // Space
            case (53, false):                                                         // Esc
                if self.model.selection.isEmpty { self.model.isPinned = false; self.collapse() } else { self.model.selection = [] }
                return nil
            case (44, false) where event.modifierFlags.contains(.shift):              // ? (⇧/)
                self.onShowShortcuts?()
                return nil
            case (0, true): self.model.selection = Set(store.ordered.map(\.id)); return nil   // ⌘A
            case (8, true):                                                           // ⌘C
                let items = self.selectedItems()
                if !items.isEmpty { store.copy(items: items) }
                return nil
            default: return event
            }
        }

        // Picking a new position moves a dragged floating island back to that edge.
        settings.$position
            .dropFirst()
            .sink { [weak settings] _ in settings?.floatingCenter = nil }
            .store(in: &cancellables)

        // Moving or restyling the island in Settings applies right away.
        settings.$position.combineLatest(settings.$style, settings.$floatingCenter)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.positionPanel() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.positionPanel()
        }

        store.itemAdded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.itemWasAdded()
                if settings.soundOnItemAdded { Sounds.play(.itemAdded) }
            }
            .store(in: &cancellables)

        // A session finished or needs you: bounce the pill.
        claudeSessions.needsAttention
            .sink { [weak self] session in
                self?.itemWasAdded()
                if settings.soundOnClaude { Sounds.play(session.status == .waiting ? .claudeNeedsYou : .claudeFinished) }
            }
            .store(in: &cancellables)

        // The collapsed pill grows and shrinks with what it shows (previews, Claude logo, count).
        store.$items.combineLatest(claudeSessions.$sessions)
            .receive(on: RunLoop.main)
            .sink { [weak self] items, sessions in self?.fitPill(itemCount: items.count, sessions: sessions) }
            .store(in: &cancellables)
    }

    // MARK: - Public

    /// ⌥⌘F or 🔍: open the shelf with the keyboard in the search box. It stays open while searching.
    func startSearch() {
        guard !hiddenForFullScreen else { return }
        if !model.isSearching { pinnedBeforeSearch = model.isPinned }
        model.showingClaude = false
        model.isPinned = true
        expand()
        model.isSearching = true
        model.searchFocusToken += 1
        panel.makeKey()
    }

    func endSearch() {
        model.isSearching = false
        model.searchText = ""
        model.isPinned = pinnedBeforeSearch
    }

    func togglePinned() {
        model.isPinned.toggle()
        if model.isPinned { expand() } else if !cursorIsOverIsland() { collapse() }
    }

    // MARK: - Layout

    private func positionPanel() {
        // At the top, prefer the built-in display with a notch; other edges use the main screen.
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let preferred = settings.position == .top ? (notched ?? NSScreen.main) : (NSScreen.main ?? notched)
        guard let target = preferred ?? NSScreen.screens.first else { return }
        screen = target

        var layout = IslandLayout.make(screen: target, position: settings.position, style: settings.style,
                                       floatingFraction: settings.floatingCenter)
        layout.collapsedExtraWidth = pillExtraWidth
        model.layout = layout
        panel.setFrame(model.layout.panelFrame(on: target), display: true)
    }

    /// Saves where the floating island was dropped (as a fraction of the screen).
    private func moveFloating(by offset: CGSize) {
        let layout = model.layout
        guard layout.isMovable else { return }
        let moved = CGPoint(x: layout.floatingCenter.x + offset.width, y: layout.floatingCenter.y + offset.height)
        let center = layout.clamped(moved, size: layout.collapsedSize)
        model.layout.floatingCenter = center // no jump while settings round-trips
        settings.floatingCenter = layout.fraction(of: center)
    }

    private var pillExtraWidth = IslandMetrics.collapsedExtraWidth

    private func fitPill(itemCount: Int, sessions: [ClaudeSession]) {
        let width = IslandLayout.pillContentWidth(itemCount: itemCount, sessions: sessions,
                                                  notchGap: model.layout.notchGap)
        guard width != pillExtraWidth else { return }
        pillExtraWidth = width
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.layout.collapsedExtraWidth = width
        }
    }

    // MARK: - Selection, Quick Look, multi-drag

    /// Selected items in shelf order; or the card under the mouse if nothing is selected.
    private func selectedItems() -> [ShelfItem] {
        let ordered = store.ordered
        let selected = ordered.filter { model.selection.contains($0.id) }
        if !selected.isEmpty { return selected }
        return ordered.filter { $0.id == model.hoveredItemID }
    }

    private func toggleQuickLook() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared(), preview.isVisible {
            preview.orderOut(nil)
            return
        }
        let urls = selectedItems().compactMap { QuickLookSource.previewURL(for: $0, store: store) }
        guard !urls.isEmpty, let preview = QLPreviewPanel.shared() else { return }
        quickLookSource.urls = urls
        // Quick Look needs Perch active for its keys (arrows, Space to close); the app you were
        // in comes back when it closes.
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { appBeforeQuickLook = front }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey() // Quick Look finds its controller through the key window
        preview.updateController()
        preview.reloadData()
        preview.currentPreviewItemIndex = 0
        preview.makeKeyAndOrderFront(nil)
    }

    private var quickLookIsOpen: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    /// Dragging a selected card while several are selected: drag them all, in one session.
    /// Returns true to keep the event from SwiftUI, whose own single-card drag would otherwise
    /// sometimes start first.
    private func handleMultiDrag(_ event: NSEvent) -> Bool {
        guard let pressed = pressItemID, model.selection.contains(pressed), model.selection.count > 1 else { return false }
        if multiDragStarted { return true }
        guard hypot(event.locationInWindow.x - pressPoint.x, event.locationInWindow.y - pressPoint.y) > 3 else {
            return true // not far enough yet, but don't let SwiftUI start a single drag either
        }
        guard let view = panel.contentView else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        let draggingItems = MultiDragSource.draggingItems(for: selectedItems(), store: store, at: point)
        guard !draggingItems.isEmpty else { return false }
        multiDragStarted = true
        store.isDraggingOut = true
        view.beginDraggingSession(with: draggingItems, event: event, source: multiDragSource)
        return true
    }

    private func cursorIsOverIsland() -> Bool {
        guard let screen else { return false }
        let margin = model.layout.hoverMargin
        return model.layout.islandRect(on: screen, expanded: model.isExpanded)
            .insetBy(dx: -margin, dy: -margin)
            .contains(NSEvent.mouseLocation)
    }

    // MARK: - Hover logic

    // MARK: - Full screen

    private func checkFullScreen() {
        let shouldHide = settings.hideInFullScreen && Self.frontAppCoversScreen(screen) && Self.videoIsPlaying()
        guard shouldHide != hiddenForFullScreen else { return }
        hiddenForFullScreen = shouldHide
        if shouldHide {
            model.isPinned = false
            collapse()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Video players and browsers keep the display awake while a video plays (and stop when it's
    /// paused). Apps that only keep the Mac awake, like the Claude app, use a different assertion.
    private static func videoIsPlaying() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let displayAwake: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        return byProcess.values.joined().contains { assertion in
            guard let type = assertion["AssertType"] as? String, displayAwake.contains(type) else { return false }
            return (assertion["AssertLevel"] as? Int ?? 255) > 0
        }
    }

    /// True when the frontmost app has a normal window exactly covering the screen. Only window
    /// bounds are read (no titles or contents), which needs no Screen Recording permission.
    private static func frontAppCoversScreen(_ screen: NSScreen?) -> Bool {
        guard let screen, let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "com.apple.finder", app.processIdentifier != getpid(),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let size = screen.frame.size
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return abs(bounds.width - size.width) < 1 && abs(bounds.height - size.height) < 1
        }
    }

    private func trackCursor() {
        if hiddenForFullScreen { return }
        // Mid-press on the island (clicking or dragging it): keep taking mouse events and
        // leave it as it is, even if the cursor is briefly outside its old frame.
        if store.isDraggingOut && NSEvent.pressedMouseButtons == 0 {
            store.isDraggingOut = false
        }
        if pressStartedOnIsland {
            if NSEvent.pressedMouseButtons == 0 { pressStartedOnIsland = false } else {
                if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
                leftAt = nil
                return
            }
        }

        // Keep the shelf open while Quick Look shows its items.
        let inside = cursorIsOverIsland() || quickLookIsOpen
        // Everywhere except the island, clicks fall through to the apps underneath.
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if inside {
            leftAt = nil
            guard !model.isExpanded else { return }
            if enteredAt == nil { enteredAt = Date() }
            // Short dwell so passing over the menu bar doesn't pop the island open;
            // open at once while dragging something in.
            let dragging = NSEvent.pressedMouseButtons != 0
            // Floating/orb: a longer hover so there's time to grab and drag it (a click opens it at once).
            let dwell = model.layout.isMovable ? 0.45 : 0.18
            if dragging || Date().timeIntervalSince(enteredAt!) > dwell { expand() }
        } else {
            enteredAt = nil
            if model.isExpanded && !model.isPinned {
                if leftAt == nil { leftAt = Date() }
                if let leftAt, Date().timeIntervalSince(leftAt) > 0.15 { collapse() }
            } else {
                leftAt = nil
            }
        }
    }

    /// Swaps the axes of a mouse-wheel event. Trackpad scrolls (precise deltas) already go sideways.
    private static func horizontalScroll(from event: NSEvent) -> NSEvent? {
        guard !event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let cg = event.cgEvent?.copy() else { return nil }
        let integerPairs: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2)
        ]
        for (vertical, horizontal) in integerPairs {
            cg.setIntegerValueField(horizontal, value: cg.getIntegerValueField(vertical))
            cg.setIntegerValueField(vertical, value: 0)
        }
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2,
                               value: cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        return NSEvent(cgEvent: cg)
    }

    private func clickedOutside() {
        guard model.isExpanded, !cursorIsOverIsland() else { return }
        model.isPinned = false
        collapse()
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func expand() {
        guard !model.isExpanded else { return }
        // Slightly under-damped spring: a small overshoot, but it settles quickly.
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.75)
        withAnimation(animation) { model.isExpanded = true }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func collapse() {
        guard model.isExpanded else { return }
        leftAt = nil
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.12) : .easeOut(duration: 0.18)
        withAnimation(animation) {
            model.isExpanded = false
            model.isDropTargeted = false
        }
        // Next time it opens, start on the shelf again, with nothing selected and no search.
        model.showingClaude = false
        model.isSearching = false
        model.searchText = ""
        model.selection = []
        model.selectionAnchor = nil
        // Give the keyboard back to the app you were in.
        if panel.isKeyWindow && !hiddenForFullScreen {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func itemWasAdded() {
        model.flashToken += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
