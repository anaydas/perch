import AppKit
import SwiftUI

/// `Perch --render-screenshots <folder>` draws the README screenshots from the app's own views,
/// filled with sample data (a temporary shelf and settings, never the user's).
@MainActor
enum ReadmeScreenshots {
    static func render(to folder: URL, theme: IslandTheme = .dark) {
        let suite = "com.anaydas.Perch.readme-screenshots"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("perch-screenshots-\(UUID().uuidString)")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temp)
        }

        let settings = AppSettings(defaults: defaults)
        settings.background = .solid // materials need a live window; solid renders the same everywhere
        settings.theme = theme
        let store = ShelfStore(settings: settings, directory: temp.appendingPathComponent("data"))
        let sessions = ClaudeSessionWatcher(settings: settings)
        let usage = ClaudeUsageWatcher(settings: settings)
        addSampleItems(to: store, files: temp.appendingPathComponent("files"))
        sessions.showSample(sampleSessions)
        usage.showSample(sampleUsage)

        // File cards load their size and icon in the background; let that finish.
        store.items.forEach { _ = store.info(for: $0) }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Drawn in an off-screen window (scroll views and other AppKit-backed views need one).
        func save(_ name: String, _ view: some View) {
            let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light))
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            defer { window.orderOut(nil) }
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                print("Couldn't render \(name)")
                return
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
            print("Wrote \(name)")
        }

        func scene(width: CGFloat, height: CGFloat, position: IslandPosition = .top, style: IslandStyle = .floating,
                   expanded: Bool, claude: Bool = false, search: String? = nil) -> some View {
            var layout = IslandLayout(position: position, style: style)
            layout.visibleFrame = CGRect(x: 0, y: 0, width: width, height: height)
            layout.collapsedExtraWidth = IslandLayout.pillContentWidth(itemCount: store.items.count,
                                                                       sessions: sessions.sessions, notchGap: 0)
            layout.floatingCenter = layout.defaultFloatingCenter
            let model = IslandViewModel()
            model.layout = layout
            model.isExpanded = expanded
            model.showingClaude = claude
            if let search { model.isSearching = true; model.searchText = search }
            let island = IslandView(model: model, store: store, settings: settings,
                                    claudeSessions: sessions, claudeUsage: usage,
                                    actions: IslandActions(togglePin: {}, openSettings: {}))
            return Desktop(width: width) {
                island.frame(width: width, height: height)
            }
        }

        save("shelf-collapsed.png", scene(width: 760, height: 64, expanded: false))
        save("shelf-open.png", scene(width: 820, height: 266, expanded: true))
        save("claude-view.png", scene(width: 820, height: 266, expanded: true, claude: true))
        save("side-panel.png", scene(width: 420, height: 560, position: .left, expanded: true))
        save("search.png", scene(width: 820, height: 266, expanded: true, search: "perch"))
        save("styles.png", stylesStrip(store: store, settings: settings, sessions: sessions, usage: usage))
    }

    // MARK: - Scenes

    /// The three collapsed styles side by side, each under a menu bar.
    private static func stylesStrip(store: ShelfStore, settings: AppSettings,
                                    sessions: ClaudeSessionWatcher, usage: ClaudeUsageWatcher) -> some View {
        HStack(spacing: 18) {
            ForEach([IslandStyle.notch, .floating, .orb]) { style in
                VStack(spacing: 10) {
                    let width: CGFloat = 260, height: CGFloat = style == .notch ? 84 : 60 // notch: menu bar sits behind it
                    let island = collapsedIsland(style: style, width: width, height: height,
                                                 store: store, settings: settings, sessions: sessions, usage: usage)
                    Desktop(width: width, menuBarBehindIsland: style == .notch) {
                        island.frame(width: width, height: height)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(style.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.25))
                }
            }
        }
        .padding(18)
        .background(Color(white: 0.96))
    }

    private static func collapsedIsland(style: IslandStyle, width: CGFloat, height: CGFloat, store: ShelfStore,
                                        settings: AppSettings, sessions: ClaudeSessionWatcher,
                                        usage: ClaudeUsageWatcher) -> IslandView {
        var layout = IslandLayout(position: .top, style: style)
        layout.visibleFrame = CGRect(x: 0, y: 0, width: width, height: height)
        layout.collapsedExtraWidth = IslandLayout.pillContentWidth(itemCount: store.items.count,
                                                                   sessions: sessions.sessions, notchGap: 0)
        layout.floatingCenter = layout.defaultFloatingCenter
        let model = IslandViewModel()
        model.layout = layout
        return IslandView(model: model, store: store, settings: settings, claudeSessions: sessions,
                          claudeUsage: usage, actions: IslandActions(togglePin: {}, openSettings: {}))
    }

    // MARK: - Sample data

    private static func addSampleItems(to store: ShelfStore, files: URL) {
        try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        func file(_ name: String, bytes: Int) -> URL {
            let url = files.appendingPathComponent(name)
            try? Data(count: bytes).write(to: url)
            return url
        }

        // Added oldest first; the shelf shows newest first.
        store.addFile(file("Assets.zip", bytes: 4_200_000))
        store.addImage(sampleImage(.chart), title: "Q3 revenue")
        store.addText("func greet(name: String) {\n    print(\"Hello, \\(name)!\")\n}")
        store.addFile(file("Design spec.pdf", bytes: 246_000))
        store.addImage(sampleImage(.sunset), title: "Wallpaper idea")
        store.addText("Ship Perch v1 on Friday. Remember to update the screenshots in the README.")
        store.addImage(sampleImage(.login), title: "Login screen")

        // Show off a fixed card and a starred one.
        if let notes = store.items.first(where: { $0.title.hasPrefix("Ship Perch") }) { store.toggleFixed(notes) }
        if let chart = store.items.first(where: { $0.title == "Q3 revenue" }) { store.toggleStar(chart) }
    }

    private static var sampleSessions: [ClaudeSession] {
        [
            ClaudeSession(id: "s1", pid: 1, title: "API refactor", cwd: "~/code/api", status: .waiting,
                          waitingFor: "input needed", source: .terminal, hostSessionId: nil, statusUpdatedAt: Date()),
            ClaudeSession(id: "s2", pid: 2, title: "Perch README", cwd: "~/code/perch", status: .working,
                          waitingFor: nil, source: .app, hostSessionId: "local_1", statusUpdatedAt: Date()),
            ClaudeSession(id: "s3", pid: 3, title: "Docs site", cwd: "~/code/docs", status: .idle,
                          waitingFor: nil, source: .app, hostSessionId: "local_2", statusUpdatedAt: Date()),
        ]
    }

    private static var sampleUsage: ClaudeUsage {
        ClaudeUsage(fiveHour: .init(usedPercent: 42, resetsAt: Date().addingTimeInterval(2 * 3600 + 18 * 60)),
                    weekly: .init(usedPercent: 18, resetsAt: Date().addingTimeInterval(3 * 86400 + 5 * 3600)),
                    updatedAt: Date(), source: .statusLine)
    }

    private enum SampleImage { case chart, sunset, login }

    private static func sampleImage(_ kind: SampleImage) -> NSImage {
        NSImage(size: NSSize(width: 480, height: 320), flipped: false) { rect in
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
            switch kind {
            case .chart:
                color(0.98, 0.98, 0.99).setFill(); rect.fill()
                let bars: [(CGFloat, NSColor)] = [(0.35, color(0.30, 0.55, 0.96)), (0.55, color(0.30, 0.55, 0.96)),
                                                   (0.48, color(0.30, 0.55, 0.96)), (0.80, color(0.85, 0.47, 0.34))]
                for (i, bar) in bars.enumerated() {
                    bar.1.setFill()
                    NSBezierPath(roundedRect: NSRect(x: 60 + CGFloat(i) * 100, y: 40, width: 64, height: 240 * bar.0),
                                 xRadius: 8, yRadius: 8).fill()
                }
            case .sunset:
                color(0.99, 0.80, 0.55).setFill(); rect.fill()
                color(0.99, 0.55, 0.35).setFill(); NSBezierPath(ovalIn: NSRect(x: 190, y: 120, width: 100, height: 100)).fill()
                let far = NSBezierPath(); far.move(to: NSPoint(x: 0, y: 0)); far.line(to: NSPoint(x: 0, y: 120))
                far.line(to: NSPoint(x: 150, y: 210)); far.line(to: NSPoint(x: 300, y: 110)); far.line(to: NSPoint(x: 480, y: 190))
                far.line(to: NSPoint(x: 480, y: 0)); far.close()
                color(0.55, 0.36, 0.45).setFill(); far.fill()
                let near = NSBezierPath(); near.move(to: NSPoint(x: 0, y: 0)); near.line(to: NSPoint(x: 0, y: 70))
                near.line(to: NSPoint(x: 220, y: 150)); near.line(to: NSPoint(x: 480, y: 60)); near.line(to: NSPoint(x: 480, y: 0)); near.close()
                color(0.30, 0.22, 0.32).setFill(); near.fill()
            case .login:
                color(0.93, 0.94, 0.97).setFill(); rect.fill()
                NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 120, y: 40, width: 240, height: 240), xRadius: 18, yRadius: 18).fill()
                color(0.30, 0.55, 0.96).setFill(); NSBezierPath(ovalIn: NSRect(x: 215, y: 200, width: 50, height: 50)).fill()
                color(0.88, 0.89, 0.92).setFill()
                NSBezierPath(roundedRect: NSRect(x: 150, y: 150, width: 180, height: 26), xRadius: 6, yRadius: 6).fill()
                NSBezierPath(roundedRect: NSRect(x: 150, y: 112, width: 180, height: 26), xRadius: 6, yRadius: 6).fill()
                color(0.30, 0.55, 0.96).setFill()
                NSBezierPath(roundedRect: NSRect(x: 150, y: 66, width: 180, height: 30), xRadius: 8, yRadius: 8).fill()
            }
            return true
        }
    }
}

/// A plain desktop with a menu bar, as a backdrop for the island.
private struct Desktop<Content: View>: View {
    let width: CGFloat
    var menuBarBehindIsland = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if !menuBarBehindIsland { menuBar }
            content
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color(red: 0.36, green: 0.49, blue: 0.69)
                if menuBarBehindIsland { menuBar }
            }
        }
        .frame(width: width)
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "applelogo").font(.system(size: 12, weight: .semibold))
            Text("Finder").font(.system(size: 12, weight: .bold))
            if width > 400 {
                ForEach(["File", "Edit", "View", "Go"], id: \.self) { Text($0).font(.system(size: 12)) }
            }
            Spacer()
            if width > 300 {
                Image(systemName: "wifi").font(.system(size: 11, weight: .semibold))
                Text("Fri 9:41 AM").font(.system(size: 12))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(width: width, height: 24)
        .background(Color.black.opacity(0.18))
    }
}
