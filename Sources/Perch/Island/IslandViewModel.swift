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
    /// Floating/orb: where the panel's top-left corner is within the screen's visible area. Normally
    /// zero (the panel covers the screen); while a card is dragged out the panel shrinks to the island.
    @Published var panelOrigin: CGPoint = .zero
    /// Quick search (🔍 or ⌥⌘F): the search box is showing, and what's typed in it.
    @Published var isSearching = false
    @Published var searchText = ""
    /// The mouse is over the search box (a click anywhere else closes it).
    var searchFieldHovered = false
    /// Bumped to move the keyboard into the search box.
    @Published var searchFocusToken = 0
    /// Selected shelf cards (click, ⌘-click, ⇧-click), for Quick Look, copy and multi-drag.
    @Published var selection: Set<UUID> = []
    /// Where a ⇧-click range starts.
    var selectionAnchor: UUID?
    /// The card under the mouse (where a press or Space applies when nothing is selected).
    var hoveredItemID: UUID?
    /// Where each visible card is, in window coordinates (top-left origin). A press is matched to a
    /// card from these, since SwiftUI's hover events are sometimes missed (right after opening or scrolling).
    var cardFrames: [UUID: CGRect] = [:]
    /// Bumped each time an item is added, to play the "got it" bounce.
    @Published var flashToken = 0
}

struct IslandActions {
    var togglePin: () -> Void
    var openSettings: () -> Void
    /// Show the selected (or hovered) cards in Quick Look.
    var quickLook: () -> Void = {}
    /// Open / close the search box.
    var startSearch: () -> Void = {}
    var endSearch: () -> Void = {}
    /// Unpin and close the shelf (Return in search, after copying).
    var dismiss: () -> Void = {}
}
