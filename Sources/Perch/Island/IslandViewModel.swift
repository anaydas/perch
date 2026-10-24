import SwiftUI

final class IslandViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var isDropTargeted = false
    @Published var filter: ShelfFilter = .all
    /// The island shows Claude sessions and usage instead of shelf cards.
    @Published var showingClaude = false
    /// Where the island sits and how big it is, from the screen and the placement settings.
    @Published var layout = IslandLayout()
    /// Floating/orb: how far the island has been dragged so far (nil when not dragging).
    @Published var dragOffset: CGSize?
    /// Selected shelf cards (click, ⌘-click, ⇧-click), for Quick Look, copy and multi-drag.
    @Published var selection: Set<UUID> = []
    /// Where a ⇧-click range starts.
    var selectionAnchor: UUID?
    /// The card under the mouse (where a press or Space applies when nothing is selected).
    var hoveredItemID: UUID?
    /// Bumped each time an item is added, to play the "got it" bounce.
    @Published var flashToken = 0
}

struct IslandActions {
    var togglePin: () -> Void
    var openSettings: () -> Void
    /// Floating/orb: the user finished dragging the island by this much.
    var moveFloating: (CGSize) -> Void = { _ in }
    /// Show the selected (or hovered) cards in Quick Look.
    var quickLook: () -> Void = {}
}
