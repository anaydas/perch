import SwiftUI

final class IslandViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var isDropTargeted = false
    @Published var filter: ShelfFilter = .all
    @Published var notchSize = CGSize(width: 190, height: 32)
    /// Bumped each time an item is added, to play the "got it" bounce.
    @Published var flashToken = 0
}

struct IslandActions {
    var togglePin: () -> Void
    var openSettings: () -> Void
}
