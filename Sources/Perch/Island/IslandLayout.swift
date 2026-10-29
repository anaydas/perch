import AppKit

/// Everything about where the island sits and how big it is, for one screen,
/// position and style. Views and hit-testing both read from this so they agree.
struct IslandLayout: Equatable {
    var position: IslandPosition = .top
    var style: IslandStyle = .notch
    /// Hardware notch to leave a gap for (only for the notch style at the top of a notched screen).
    var notchGap: CGFloat = 0
    /// Thickness of the collapsed notch-style island at the top (notch or menu bar height).
    var topBarHeight: CGFloat = 24
    /// Distance from the screen edge (or menu bar / Dock) to the island.
    var edgeInset: CGFloat = 0
    /// The screen's usable area (without menu bar and Dock), in screen coordinates.
    var visibleFrame: CGRect = .zero
    /// Room the collapsed pill's content needs besides the notch gap; follows the content
    /// (previews, Claude logo, item count), see `pillContentWidth`.
    var collapsedExtraWidth: CGFloat = IslandMetrics.collapsedExtraWidth
    /// Movable styles only: centre of the collapsed island in panel coordinates
    /// (the panel covers `visibleFrame`; origin top left, y down).
    var floatingCenter: CGPoint = .zero

    var isVertical: Bool { position.isVertical }
    var isAttached: Bool { style.isAttached }
    /// Floating and orb can be dragged anywhere on screen.
    var isMovable: Bool { style == .floating || style == .orb }

    static let floatingGap: CGFloat = 6

    // MARK: - Sizes (island body, without the ears)

    var collapsedSize: CGSize {
        switch style {
        case .orb:
            return CGSize(width: 40, height: 40)
        case .notch, .floating:
            if isVertical { return CGSize(width: 30, height: 112) }
            let thickness = position == .top && style == .notch ? topBarHeight : 28
            return CGSize(width: notchGap + collapsedExtraWidth, height: thickness)
        }
    }

    var expandedSize: CGSize {
        if isVertical {
            return CGSize(width: IslandMetrics.sidePanelWidth,
                          height: min(IslandMetrics.sidePanelMaxHeight, visibleFrame.height - 2 * Self.floatingGap))
        }
        return CGSize(width: IslandMetrics.expandedWidth, height: contentLeadInset + IslandMetrics.expandedBodyHeight)
    }

    func size(expanded: Bool) -> CGSize { expanded ? expandedSize : collapsedSize }

    /// Space before the expanded content along the top: clears the notch / menu bar
    /// when the island is joined to the top of the screen.
    var contentLeadInset: CGFloat {
        position == .top && isAttached ? topBarHeight + 6 : 14
    }

    /// Ear radius where an attached island meets the edge (0 for detached styles).
    func ear(expanded: Bool) -> CGFloat {
        guard isAttached else { return 0 }
        return expanded ? IslandMetrics.earExpanded : IslandMetrics.earCollapsed
    }

    /// Corner radius of the far corners (attached) or all corners (detached).
    func corner(expanded: Bool) -> CGFloat {
        if isAttached { return expanded ? IslandMetrics.bottomExpanded : IslandMetrics.bottomCollapsed }
        return expanded ? 22 : min(collapsedSize.width, collapsedSize.height) / 2
    }

    /// Body size plus the ears, which stick out along the edge.
    func outerSize(expanded: Bool) -> CGSize {
        let body = size(expanded: expanded), e = ear(expanded: expanded)
        return isVertical ? CGSize(width: body.width, height: body.height + 2 * e)
                          : CGSize(width: body.width + 2 * e, height: body.height)
    }

    // MARK: - Floating

    /// Default spot for the floating island: against the chosen edge.
    var defaultFloatingCenter: CGPoint {
        let s = collapsedSize, w = visibleFrame.width, h = visibleFrame.height, g = Self.floatingGap
        switch position {
        case .top: return CGPoint(x: w / 2, y: g + s.height / 2)
        case .left: return CGPoint(x: g + s.width / 2, y: h / 2)
        case .right: return CGPoint(x: w - g - s.width / 2, y: h / 2)
        }
    }

    /// Keeps an island of `size` centred near `point` fully inside the panel.
    func clamped(_ point: CGPoint, size: CGSize) -> CGPoint {
        let g = Self.floatingGap, w = visibleFrame.width, h = visibleFrame.height
        let halfW = size.width / 2, halfH = size.height / 2
        return CGPoint(x: min(max(point.x, g + halfW), max(g + halfW, w - g - halfW)),
                       y: min(max(point.y, g + halfH), max(g + halfH, h - g - halfH)))
    }

    /// Centre of the floating island in panel coordinates. The open shelf shifts as
    /// needed to stay on screen; `offset` is a drag in progress.
    func floatingCenter(expanded: Bool, offset: CGSize = .zero) -> CGPoint {
        let moved = CGPoint(x: floatingCenter.x + offset.width, y: floatingCenter.y + offset.height)
        return clamped(moved, size: size(expanded: expanded))
    }

    /// Converts a dragged centre (panel coordinates) to the fraction stored in settings.
    func fraction(of center: CGPoint) -> CGPoint {
        CGPoint(x: center.x / max(visibleFrame.width, 1), y: center.y / max(visibleFrame.height, 1))
    }

    // MARK: - Panel

    /// The mostly transparent panel that hosts the island.
    var panelSize: CGSize {
        if isMovable { return visibleFrame.size }
        return isVertical ? CGSize(width: IslandMetrics.sidePanelWidth + 60,
                                   height: min(visibleFrame.height, IslandMetrics.sidePanelMaxHeight + 60))
                          : IslandMetrics.panelSize
    }

    static func make(screen: NSScreen, position: IslandPosition, style: IslandStyle,
                     floatingFraction: CGPoint?) -> IslandLayout {
        var layout = IslandLayout(position: position, style: style)
        let frame = screen.frame, visible = screen.visibleFrame
        let notched = screen.safeAreaInsets.top > 0
        layout.visibleFrame = visible

        layout.topBarHeight = notched ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        if position == .top && style == .notch && notched {
            layout.notchGap = 190 // fallback if the system doesn't report the notch areas
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                layout.notchGap = frame.width - left.width - right.width
            }
        }

        switch position {
        case .top:
            // Detached styles sit below the menu bar so they never cover menus.
            layout.edgeInset = style.isAttached ? 0 : (frame.maxY - visible.maxY) + floatingGap
        case .left:
            layout.edgeInset = (visible.minX - frame.minX) + (style.isAttached ? 0 : floatingGap)
        case .right:
            layout.edgeInset = (frame.maxX - visible.maxX) + (style.isAttached ? 0 : floatingGap)
        }

        if layout.isMovable {
            let wanted = floatingFraction.map { CGPoint(x: $0.x * visible.width, y: $0.y * visible.height) }
                ?? layout.defaultFloatingCenter
            layout.floatingCenter = layout.clamped(wanted, size: layout.collapsedSize)
        }
        return layout
    }

    /// Panel frame in screen coordinates.
    func panelFrame(on screen: NSScreen) -> NSRect {
        let frame = screen.frame, visible = screen.visibleFrame, size = panelSize
        if isMovable { return visible }
        switch position {
        case .top:
            return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        case .left:
            return NSRect(x: frame.minX, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        case .right:
            return NSRect(x: frame.maxX - size.width, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    /// Island body in screen coordinates (y grows upwards in AppKit), for hit-testing.
    func islandRect(on screen: NSScreen, expanded: Bool) -> CGRect {
        let frame = screen.frame, visible = screen.visibleFrame
        let s = size(expanded: expanded)
        if isMovable {
            let c = floatingCenter(expanded: expanded)
            return CGRect(x: visible.minX + c.x - s.width / 2, y: visible.maxY - c.y - s.height / 2,
                          width: s.width, height: s.height)
        }
        switch position {
        case .top:
            return CGRect(x: frame.midX - s.width / 2, y: frame.maxY - edgeInset - s.height, width: s.width, height: s.height)
        case .left:
            return CGRect(x: frame.minX + edgeInset, y: visible.midY - s.height / 2, width: s.width, height: s.height)
        case .right:
            return CGRect(x: frame.maxX - edgeInset - s.width, y: visible.midY - s.height / 2, width: s.width, height: s.height)
        }
    }

    var hoverMargin: CGFloat { 6 }

    /// Width the horizontal pill needs (besides the notch gap) to fit its content without
    /// squeezing: previews on the left; Claude logo, count and dot on the right.
    /// Shown next to the tray icon while the shelf is empty.
    static let emptyPillLabel = "Shelf"

    static func pillContentWidth(itemCount: Int, sessions: [ClaudeSession], notchGap: CGFloat) -> CGFloat {
        let previews = min(itemCount, 3)
        let label = (emptyPillLabel as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
        let left: CGFloat = previews == 0 ? 14 + 5 + ceil(label) : 16 + CGFloat(previews - 1) * 10
        var right: CGFloat = 0
        if !sessions.isEmpty {
            right += 11
            if sessions.filter({ $0.status == .waiting }).count > 1 { right += 12 }
        }
        if right > 0 { right += 5 }
        right += CGFloat(String(itemCount).count) * 7.5 + 5 + 5 // digits, spacing, dot (shown even at 0)
        let padding: CGFloat = 24, gap: CGFloat = 12
        // With a notch the two sides sit either side of it, so each side gets the wider one's room.
        let content = notchGap > 0 ? 2 * max(left, right) : left + gap + right
        return max(64, (padding + content).rounded(.up))
    }
}
