import SwiftUI

enum IslandBackground: String, CaseIterable, Identifiable {
    case solid, transparent, glass
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum IslandOutline: String, CaseIterable, Identifiable {
    case none, hairline, accent, glow, double, pulse
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Which screen edge the island sits on.
enum IslandPosition: String, CaseIterable, Identifiable {
    case top, left, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var isVertical: Bool { self == .left || self == .right }
}

/// How the collapsed island looks. Every style opens to the same shelf.
enum IslandStyle: String, CaseIterable, Identifiable {
    case notch, floating, orb
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notch: return "Notch"
        case .floating: return "Floating"
        case .orb: return "Orb"
        }
    }
    /// Notch is joined to the screen edge; floating and orb sit a little away from it.
    var isAttached: Bool { self == .notch }
}

enum OutlineTint: String, CaseIterable, Identifiable {
    case blue, orange, purple, green, white
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .purple: return Color(red: 0.75, green: 0.35, blue: 0.95)
        case .green: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .white: return Color(white: 0.96)
        }
    }
}

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var position: IslandPosition { didSet { defaults.set(position.rawValue, forKey: Keys.position) } }
    @Published var style: IslandStyle { didSet { defaults.set(style.rawValue, forKey: Keys.style) } }
    /// Where the user dragged the floating island or orb: its centre as a fraction of the screen's
    /// usable area (0…1, from the top left), so it survives resolution changes. nil = default spot.
    @Published var floatingCenter: CGPoint? {
        didSet {
            if let p = floatingCenter { defaults.set([p.x, p.y], forKey: Keys.floatingCenter) }
            else { defaults.removeObject(forKey: Keys.floatingCenter) }
        }
    }
    /// Filter tabs (All, Images, Text, Files, Recent) in the shelf header. Off: the shelf shows everything.
    @Published var showFilters: Bool { didSet { defaults.set(showFilters, forKey: Keys.showFilters) } }
    @Published var background: IslandBackground { didSet { defaults.set(background.rawValue, forKey: Keys.background) } }
    @Published var outline: IslandOutline { didSet { defaults.set(outline.rawValue, forKey: Keys.outline) } }
    @Published var tint: OutlineTint { didSet { defaults.set(tint.rawValue, forKey: Keys.tint) } }
    @Published var autoCatchScreenshots: Bool { didSet { defaults.set(autoCatchScreenshots, forKey: Keys.screenshots) } }
    @Published var clipboardHistory: Bool { didSet { defaults.set(clipboardHistory, forKey: Keys.clipboard) } }
    @Published var hideSensitive: Bool { didSet { defaults.set(hideSensitive, forKey: Keys.sensitive) } }
    /// Master switch for everything Claude (sessions, usage, logo). Off: no Claude polling at all.
    @Published var showClaude: Bool { didSet { defaults.set(showClaude, forKey: Keys.claude) } }
    @Published var showClaudeSessions: Bool { didSet { defaults.set(showClaudeSessions, forKey: Keys.claudeSessions) } }
    @Published var showClaudeUsage: Bool { didSet { defaults.set(showClaudeUsage, forKey: Keys.claudeUsage) } }
    /// 0 = never expire.
    @Published var expiryHours: Int { didSet { defaults.set(expiryHours, forKey: Keys.expiry) } }

    private enum Keys {
        static let background = "background"
        static let showFilters = "showFilters"
        static let position = "position"
        static let style = "style"
        static let floatingCenter = "floatingCenter"
        static let outline = "outline"
        static let tint = "tint"
        static let screenshots = "autoCatchScreenshots"
        static let clipboard = "clipboardHistory"
        static let sensitive = "hideSensitive"
        static let claude = "showClaude"
        static let claudeSessions = "showClaudeSessions"
        static let claudeUsage = "showClaudeUsage"
        static let expiry = "expiryHours"
    }

    init() {
        Self.migrateFromNotchShelf()
        let d = UserDefaults.standard
        position = IslandPosition(rawValue: d.string(forKey: Keys.position) ?? "") ?? .top
        style = IslandStyle(rawValue: d.string(forKey: Keys.style) ?? "") ?? .notch
        if let p = d.array(forKey: Keys.floatingCenter) as? [Double], p.count == 2 {
            floatingCenter = CGPoint(x: p[0], y: p[1])
        } else {
            floatingCenter = nil
        }
        showFilters = d.object(forKey: Keys.showFilters) as? Bool ?? false
        background = IslandBackground(rawValue: d.string(forKey: Keys.background) ?? "") ?? .glass
        outline = IslandOutline(rawValue: d.string(forKey: Keys.outline) ?? "") ?? .glow
        tint = OutlineTint(rawValue: d.string(forKey: Keys.tint) ?? "") ?? .blue
        autoCatchScreenshots = d.object(forKey: Keys.screenshots) as? Bool ?? true
        clipboardHistory = d.object(forKey: Keys.clipboard) as? Bool ?? true
        hideSensitive = d.object(forKey: Keys.sensitive) as? Bool ?? true
        showClaude = d.object(forKey: Keys.claude) as? Bool ?? true
        showClaudeSessions = d.object(forKey: Keys.claudeSessions) as? Bool ?? true
        showClaudeUsage = d.object(forKey: Keys.claudeUsage) as? Bool ?? true
        expiryHours = d.object(forKey: Keys.expiry) as? Int ?? 72
    }

    /// The app used to be called Notch Shelf (bundle id com.anaydas.NotchShelf):
    /// copy its settings across once, without overwriting anything already set.
    private static func migrateFromNotchShelf() {
        let d = UserDefaults.standard
        let flag = "migratedFromNotchShelf"
        guard !d.bool(forKey: flag) else { return }
        if let old = d.persistentDomain(forName: "com.anaydas.NotchShelf") {
            for (key, value) in old where d.object(forKey: key) == nil {
                d.set(value, forKey: key)
            }
        }
        d.set(true, forKey: flag)
    }

}
