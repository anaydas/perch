import AppKit
import Combine
import SwiftUI

/// Positions the island over the notch and decides when it expands or collapses.
final class IslandController {
    let model = IslandViewModel()
    var onOpenSettings: (() -> Void)?

    private let store: ShelfStore
    private let settings: AppSettings
    private let panel: IslandPanel
    private var screen: NSScreen?
    private var trackingTimer: Timer?
    private var leftAt: Date?
    private var cancellables = Set<AnyCancellable>()

    init(store: ShelfStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: IslandMetrics.panelSize))

        let actions = IslandActions(
            togglePin: { [weak self] in self?.togglePinned() },
            openSettings: { [weak self] in self?.onOpenSettings?() }
        )
        let root = IslandView(model: model, store: store, settings: settings, actions: actions)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: IslandMetrics.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        positionPanel()
        panel.orderFrontRegardless()

        // Poll the cursor: cheap, and it also works while dragging files from other apps.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.trackCursor()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.positionPanel()
        }

        store.itemAdded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.itemWasAdded() }
            .store(in: &cancellables)
    }

    // MARK: - Public

    func togglePinned() {
        model.isPinned.toggle()
        if model.isPinned { expand() } else if !cursorIsOverIsland() { collapse() }
    }

    // MARK: - Layout

    private func positionPanel() {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let target = notched ?? NSScreen.main ?? NSScreen.screens.first else { return }
        screen = target

        let frame = target.frame
        var notchWidth: CGFloat = 190
        var notchHeight: CGFloat = NSStatusBar.system.thickness
        if target.safeAreaInsets.top > 0 {
            notchHeight = target.safeAreaInsets.top
            if let left = target.auxiliaryTopLeftArea, let right = target.auxiliaryTopRightArea {
                notchWidth = frame.width - left.width - right.width
            }
        }
        model.notchSize = CGSize(width: notchWidth, height: notchHeight)

        let size = IslandMetrics.panelSize
        panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                              y: frame.maxY - size.height,
                              width: size.width,
                              height: size.height),
                       display: true)
    }

    /// Island body in screen coordinates (y grows upwards in AppKit).
    private func islandRect() -> CGRect {
        guard let screen else { return .zero }
        let notch = model.notchSize
        let size = model.isExpanded
            ? CGSize(width: IslandMetrics.expandedWidth, height: notch.height + IslandMetrics.expandedBodyHeight)
            : CGSize(width: notch.width + IslandMetrics.collapsedExtraWidth, height: notch.height)
        return CGRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    private func cursorIsOverIsland() -> Bool {
        islandRect().insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    // MARK: - Hover logic

    private func trackCursor() {
        let inside = cursorIsOverIsland()
        // Everywhere except the island, clicks fall through to the apps underneath.
        panel.ignoresMouseEvents = !inside

        if inside {
            leftAt = nil
            if !model.isExpanded { expand() }
        } else if model.isExpanded && !model.isPinned {
            if leftAt == nil { leftAt = Date() }
            if let leftAt, Date().timeIntervalSince(leftAt) > 0.35 { collapse() }
        } else {
            leftAt = nil
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func expand() {
        guard !model.isExpanded else { return }
        // Under-damped spring = the wobble: it overshoots, squishes back and settles.
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.55)
        withAnimation(animation) { model.isExpanded = true }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func collapse() {
        guard model.isExpanded else { return }
        leftAt = nil
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.78)
        withAnimation(animation) {
            model.isExpanded = false
            model.isDropTargeted = false
        }
    }

    private func itemWasAdded() {
        model.flashToken += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
