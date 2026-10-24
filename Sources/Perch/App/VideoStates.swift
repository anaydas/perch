import AppKit
import SwiftUI

/// `Perch --render-video-states <folder>` draws every app state the intro video shows, on a
/// transparent background, from the app's own views and sample data (never the user's).
/// scripts/make-video.swift then animates them, adds music and sound effects, and encodes the video.
@MainActor
enum VideoStates {
    static func render(to folder: URL) {
        let suite = "com.anaydas.Perch.video-states"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("perch-video-\(UUID().uuidString)")
        let files = temp.appendingPathComponent("files")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }

        let settings = AppSettings(defaults: defaults)
        settings.background = .solid
        let store = ShelfStore(settings: settings, directory: temp.appendingPathComponent("data"))
        let sessions = ClaudeSessionWatcher(settings: settings)
        let usage = ClaudeUsageWatcher(settings: settings)
        ReadmeScreenshots.addSampleItems(to: store, files: files)
        store.items.filter(\.isFixed).forEach(store.toggleFixed)
        store.items.filter(\.isStarred).forEach(store.toggleStar)
        sessions.showSample(ReadmeScreenshots.sampleSessions)
        usage.showSample(ReadmeScreenshots.sampleUsage)
        settle(store)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func save(_ name: String, _ view: some View, size: CGSize) {
            let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            defer { window.orderOut(nil) }
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
            print("Wrote \(name)")
        }

        /// Just the island, with room around it for the outline glow.
        func island(_ name: String, style: IslandStyle = .floating, position: IslandPosition = .top, expanded: Bool,
                    claude: Bool = false, search: String? = nil, selection: Set<UUID> = []) {
            let pad: CGFloat = 24
            var layout = IslandLayout(position: position, style: style)
            layout.visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 600)
            layout.collapsedExtraWidth = IslandLayout.pillContentWidth(itemCount: store.items.count,
                                                                       sessions: sessions.sessions, notchGap: 0)
            let outer = layout.outerSize(expanded: expanded)
            let size = CGSize(width: outer.width + 2 * pad, height: outer.height + (style.isAttached ? pad : 2 * pad))
            layout.visibleFrame = CGRect(origin: .zero, size: size)
            layout.floatingCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            let model = IslandViewModel()
            model.layout = layout
            model.isExpanded = expanded
            model.showingClaude = claude
            model.selection = selection
            if let search { model.isSearching = true; model.searchText = search }
            let view = IslandView(model: model, store: store, settings: settings, claudeSessions: sessions,
                                  claudeUsage: usage, actions: IslandActions(togglePin: {}, openSettings: {}))
            save(name, view, size: size)
        }

        // 1. The shelf to start with
        island("pill-0.png", expanded: false)
        island("shelf-0.png", expanded: true)

        // 2. A screenshot lands
        store.addImage(dashboardImage(), title: "Screenshot 9.41.12 AM")
        settle(store)
        island("shelf-1.png", expanded: true)

        // 3. A screen recording lands (a short sample video that ships with macOS)
        let sampleVideo = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/Slideshows.framework/Versions/A/Resources/Content/Styles/KenBurns.mrbStyle/Contents/Resources/Preview.mov")
        let recording = files.appendingPathComponent("Screen Recording 9.45.03 AM.mov")
        if (try? FileManager.default.copyItem(at: sampleVideo, to: recording)) != nil {
            store.addFile(recording)
            settle(store)
        }
        island("shelf-2.png", expanded: true)

        // 4. Something is copied
        store.addText("Lunch with the design team moved to 1 pm")
        settle(store)
        island("pill.png", expanded: false)
        island("shelf-3.png", expanded: true)

        // Looks: side panel, styles, light theme, accent colours
        island("side.png", position: .left, expanded: true)
        settings.outline = .none
        island("style-notch.png", style: .notch, expanded: false)
        settings.outline = .glow
        island("style-orb.png", style: .orb, expanded: false)
        settings.theme = .light
        island("shelf-light.png", expanded: true)
        settings.theme = .dark
        settings.tint = .orange
        island("shelf-orange.png", expanded: true)
        settings.tint = .purple
        island("shelf-purple.png", expanded: true)
        settings.tint = .blue

        // Selection, search, Claude
        let firstThree = Set(store.ordered.prefix(3).map(\.id))
        island("shelf-select.png", expanded: true, selection: firstThree)
        island("search.png", expanded: true, search: "q3")
        island("claude.png", expanded: true, claude: true)

        // Fixed at the front and starred
        if let notes = store.items.first(where: { $0.title.hasPrefix("Ship Perch") }) { store.toggleFixed(notes) }
        if let chart = store.items.first(where: { $0.title == "Q3 revenue" }) { store.toggleStar(chart) }
        settle(store)
        island("shelf-fixed.png", expanded: true)

        // A secret (blurred by the video script; offscreen snapshots can't capture blur)
        settings.hideSensitive = false
        store.addText("STRIPE_SECRET_KEY=sk_live_EXAMPLE_not_a_real_key_000000")
        settle(store)
        island("shelf-secret.png", expanded: true)

        // The shortcuts window, and loose images the video uses
        save("shortcuts.png", ShortcutsView().environment(\.colorScheme, .dark), size: CGSize(width: 520, height: 640))
        if let png = dashboardImage().pngData() {
            try? png.write(to: folder.appendingPathComponent("drag-thumb.png"))
        }
        for (name, kind) in [("thumb-sunset.png", ReadmeScreenshots.SampleImage.sunset), ("thumb-login.png", .login), ("thumb-chart.png", .chart)] {
            if let png = ReadmeScreenshots.sampleImage(kind).pngData() { try? png.write(to: folder.appendingPathComponent(name)) }
        }
        print("Done")
    }

    private static func settle(_ store: ShelfStore) {
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        store.items.forEach { _ = store.info(for: $0) }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    }

    /// The "screenshot" that lands in the video: a small analytics dashboard.
    static func dashboardImage() -> NSImage {
        NSImage(size: NSSize(width: 480, height: 320), flipped: false) { rect in
            func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
            c(0.97, 0.97, 0.99).setFill(); rect.fill()
            c(0.13, 0.15, 0.22).setFill(); NSRect(x: 0, y: 0, width: 90, height: 320).fill()
            for i in 0..<5 {
                c(0.35, 0.40, 0.55).setFill()
                NSBezierPath(roundedRect: NSRect(x: 18, y: 250 - CGFloat(i) * 34, width: 54, height: 10), xRadius: 5, yRadius: 5).fill()
            }
            let tiles: [NSColor] = [c(0.30, 0.55, 0.96), c(0.85, 0.47, 0.34), c(0.20, 0.70, 0.55)]
            for (i, color) in tiles.enumerated() {
                NSColor.white.setFill()
                let tile = NSRect(x: 110 + CGFloat(i) * 120, y: 220, width: 108, height: 76)
                NSBezierPath(roundedRect: tile, xRadius: 10, yRadius: 10).fill()
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: tile.minX + 12, y: tile.minY + 14, width: 60, height: 14), xRadius: 7, yRadius: 7).fill()
            }
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(x: 110, y: 24, width: 348, height: 180), xRadius: 12, yRadius: 12).fill()
            let line = NSBezierPath()
            let points: [CGFloat] = [40, 70, 55, 100, 90, 130, 120, 150]
            for (i, y) in points.enumerated() {
                let p = NSPoint(x: 130 + CGFloat(i) * 44, y: 40 + y)
                if i == 0 { line.move(to: p) } else { line.line(to: p) }
            }
            line.lineWidth = 5
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            c(0.30, 0.55, 0.96).setStroke()
            line.stroke()
            return true
        }
    }
}
