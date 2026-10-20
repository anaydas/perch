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

    @Published var background: IslandBackground { didSet { defaults.set(background.rawValue, forKey: Keys.background) } }
    @Published var outline: IslandOutline { didSet { defaults.set(outline.rawValue, forKey: Keys.outline) } }
    @Published var tint: OutlineTint { didSet { defaults.set(tint.rawValue, forKey: Keys.tint) } }
    @Published var autoCatchScreenshots: Bool { didSet { defaults.set(autoCatchScreenshots, forKey: Keys.screenshots) } }
    @Published var clipboardHistory: Bool { didSet { defaults.set(clipboardHistory, forKey: Keys.clipboard) } }
    @Published var hideSensitive: Bool { didSet { defaults.set(hideSensitive, forKey: Keys.sensitive) } }
    /// 0 = never expire.
    @Published var expiryHours: Int { didSet { defaults.set(expiryHours, forKey: Keys.expiry) } }

    private enum Keys {
        static let background = "background"
        static let outline = "outline"
        static let tint = "tint"
        static let screenshots = "autoCatchScreenshots"
        static let clipboard = "clipboardHistory"
        static let sensitive = "hideSensitive"
        static let expiry = "expiryHours"
    }

    init() {
        let d = UserDefaults.standard
        background = IslandBackground(rawValue: d.string(forKey: Keys.background) ?? "") ?? .glass
        outline = IslandOutline(rawValue: d.string(forKey: Keys.outline) ?? "") ?? .glow
        tint = OutlineTint(rawValue: d.string(forKey: Keys.tint) ?? "") ?? .blue
        autoCatchScreenshots = d.object(forKey: Keys.screenshots) as? Bool ?? true
        clipboardHistory = d.object(forKey: Keys.clipboard) as? Bool ?? true
        hideSensitive = d.object(forKey: Keys.sensitive) as? Bool ?? true
        expiryHours = d.object(forKey: Keys.expiry) as? Int ?? 72
    }
}
