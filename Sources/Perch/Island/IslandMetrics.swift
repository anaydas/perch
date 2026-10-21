import CoreGraphics

enum IslandMetrics {
    /// Fixed panel that hosts the island; only the island area takes mouse events.
    static let panelSize = CGSize(width: 900, height: 440)

    static let expandedWidth: CGFloat = 760
    /// Height of the expanded island below the notch.
    static let expandedBodyHeight: CGFloat = 234
    /// How far the small pill sticks out past the notch (both sides together).
    static let collapsedExtraWidth: CGFloat = 96

    static let earCollapsed: CGFloat = 10
    static let earExpanded: CGFloat = 18
    static let bottomCollapsed: CGFloat = 12
    static let bottomExpanded: CGFloat = 28

    /// Expanded island on the left or right edge.
    static let sidePanelWidth: CGFloat = 300
    static let sidePanelMaxHeight: CGFloat = 620

    static let cardWidth: CGFloat = 104
    static let cardHeight: CGFloat = 126
    static let cardSpacing: CGFloat = 8
}
