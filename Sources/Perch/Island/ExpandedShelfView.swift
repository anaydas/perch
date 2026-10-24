import AppKit
import SwiftUI

struct ExpandedShelfView: View {
    @Environment(\.islandAccent) private var accent
    @ObservedObject var model: IslandViewModel
    @ObservedObject var store: ShelfStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var claudeSessions: ClaudeSessionWatcher
    @ObservedObject var claudeUsage: ClaudeUsageWatcher
    let actions: IslandActions

    /// Without filter tabs, the shelf always shows everything.
    private var filter: ShelfFilter { settings.showFilters ? model.filter : .all }

    private var filteredItems: [ShelfItem] {
        switch filter {
        case .all: return store.ordered
        case .images: return store.ordered.filter { $0.kind == .image }
        case .text: return store.ordered.filter { $0.kind == .text }
        case .files: return store.ordered.filter { $0.kind == .file }
        case .recent: return store.recent
        }
    }

    private var query: String { model.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The filter, then the search: title, the text of text cards, and file names.
    private var visibleItems: [ShelfItem] {
        let items = filteredItems
        guard model.isSearching, !query.isEmpty else { return items }
        return items.filter { item in
            [item.title, item.text, item.fileURL?.lastPathComponent].contains { $0?.localizedStandardContains(query) ?? false }
        }
    }

    /// The Claude logo (top right) is there when any Claude feature is on.
    private var claudeAvailable: Bool {
        settings.showClaude && (settings.showClaudeSessions || settings.showClaudeUsage)
    }
    /// The island shows the Claude view (sessions + usage) instead of the shelf.
    private var showingClaude: Bool { model.showingClaude && claudeAvailable }
    /// Left/right edge: a tall side panel with a card grid that scrolls down.
    private var vertical: Bool { model.layout.isVertical }

    var body: some View {
        VStack(alignment: .leading, spacing: vertical ? 10 : 12) {
            header

            if vertical && !showingClaude && settings.showFilters {
                filterMenu
            }

            Group {
                if showingClaude {
                    if claudeSessions.sessions.isEmpty {
                        EmptyClaudeView(sessionsEnabled: settings.showClaudeSessions)
                    } else {
                        cards(claudeSessions.sessions) { SessionCardView(session: $0, watcher: claudeSessions) }
                    }
                } else if visibleItems.isEmpty && model.isSearching && !query.isEmpty {
                    NoMatchesView(query: query)
                } else if visibleItems.isEmpty {
                    EmptyShelfView(filter: filter)
                } else {
                    cards(visibleItems) { ItemCardView(item: $0, store: store, settings: settings, selection: selection(for: $0)) }
                }
            }
            .frame(maxHeight: vertical ? .infinity : nil)
            // Something from another app is being dragged over: show the drop area on top of the
            // cards (never in place of them, and never for a card dragged out of this shelf).
            .overlay {
                if model.isDropTargeted && !store.isDraggingOut {
                    DropZoneView()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }

            footer
        }
        .padding(.horizontal, vertical ? 14 : 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func cards<Item: Identifiable, Card: View>(_ items: [Item], @ViewBuilder card: @escaping (Item) -> Card) -> some View {
        if vertical {
            CardGrid(items: items, card: card)
        } else {
            CardStrip(items: items, card: card)
        }
    }

    // MARK: - Search

    /// Return: copy the first match and close the shelf.
    private func copyFirstMatch() {
        guard let first = visibleItems.first else { return }
        store.copy(first)
        actions.dismiss()
    }

    /// Esc: clear what's typed; on an empty box, leave search.
    private func escapeSearch() {
        if model.searchText.isEmpty { actions.endSearch() } else { model.searchText = "" }
    }

    // MARK: - Selection

    private func selection(for item: ShelfItem) -> CardSelection {
        let selected = selectedItems
        return CardSelection(
            isSelected: model.selection.contains(item.id),
            count: selected.count,
            onTap: { select(item) },
            onHover: { inside in
                if inside { model.hoveredItemID = item.id } else if model.hoveredItemID == item.id { model.hoveredItemID = nil }
            },
            onQuickLook: {
                if !model.selection.contains(item.id) { model.selection = [item.id]; model.selectionAnchor = item.id }
                actions.quickLook()
            },
            onCopyAll: { store.copy(items: selectedItems) },
            onRemoveAll: {
                selectedItems.forEach(store.remove)
                model.selection = []
            }
        )
    }

    /// Selected items, in the order they're shown.
    private var selectedItems: [ShelfItem] { visibleItems.filter { model.selection.contains($0.id) } }

    /// Click: just this card. ⌘-click: add or remove it. ⇧-click: everything from the last clicked card.
    private func select(_ item: ShelfItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
            model.selectionAnchor = item.id
        } else if flags.contains(.shift), let anchor = model.selectionAnchor,
                  let from = visibleItems.firstIndex(where: { $0.id == anchor }),
                  let to = visibleItems.firstIndex(where: { $0.id == item.id }) {
            model.selection = Set(visibleItems[min(from, to)...max(from, to)].map(\.id))
        } else {
            model.selection = [item.id]
            model.selectionAnchor = item.id
        }
    }

    /// The side panel is too narrow for the segmented tabs.
    private var filterMenu: some View {
        Picker("Show", selection: $model.filter) {
            ForEach(ShelfFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if showingClaude {
                HStack(spacing: 7) {
                    ClaudeMarkView(status: claudeSessions.sessions.first?.status ?? .idle, size: 14)
                    Text("Claude")
                        .font(.system(size: 14, weight: .semibold))
                    if settings.showClaudeSessions {
                        let count = claudeSessions.sessions.count
                        countBadge(count == 1 ? "1 session" : "\(count) sessions")
                    }
                }
                Spacer(minLength: 8)
            } else if model.isSearching {
                SearchField(text: $model.searchText, focusToken: model.searchFocusToken,
                            onSubmit: copyFirstMatch, onEscape: escapeSearch)
                if !query.isEmpty {
                    countBadge("\(visibleItems.count) of \(filteredItems.count)")
                }
                Spacer(minLength: 4)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(accent)
                    Text("Shelf")
                        .font(.system(size: 14, weight: .semibold))
                    countBadge("\(store.items.count)")
                }

                Spacer(minLength: 8)

                if !vertical && settings.showFilters {
                    Picker("Filter", selection: $model.filter) {
                        ForEach(ShelfFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 330)

                    Spacer(minLength: 8)
                }
            }

            HStack(spacing: 6) {
                if claudeAvailable {
                    ClaudeButton(active: showingClaude,
                                 status: claudeSessions.sessions.first?.status ?? .idle,
                                 fiveHourPercent: claudeUsage.usage?.currentFiveHourPercent) {
                        model.showingClaude.toggle()
                    }
                }
                if !showingClaude {
                    IconButton(systemName: model.isSearching ? "xmark" : "magnifyingglass",
                               help: model.isSearching ? "Close search (Esc)" : "Search the shelf (⌥⌘F)",
                               highlighted: false,
                               action: model.isSearching ? actions.endSearch : actions.startSearch)
                }
                IconButton(systemName: model.isPinned ? "pin.fill" : "pin",
                           help: model.isPinned ? "Let the island close" : "Keep the island open (⌥Space)",
                           highlighted: model.isPinned,
                           action: actions.togglePin)
                IconButton(systemName: "gearshape", help: "Settings", highlighted: false, action: actions.openSettings)
            }
        }
        .frame(height: 30)
        // Floating/orb: drag the open shelf around by its header.
        .contentShape(Rectangle())
        .gesture(model.layout.isMovable ? IslandMoveGesture.make(model: model, actions: actions) : nil)
        .help(model.layout.isMovable ? "Drag to move" : "")
    }

    private func countBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
    }

    /// Shelf: hints. Claude view: the full usage meters.
    @ViewBuilder
    private var footer: some View {
        if showingClaude, let usage = claudeUsage.usage {
            ClaudeUsageBar(usage: usage, stacked: vertical)
        } else if vertical {
            Text(showingClaude ? "Click a session to open it" : "Drag in to pin · drag out to use")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Text(showingClaude ? "Click a session to open it · right-click for more"
                     : model.isSearching ? "Return copies the first match · Esc clears"
                     : "Drag in to pin · drag out to use · double-click to open")
                Spacer()
                Text(showingClaude ? "Click the Claude logo to go back"
                     : model.isSearching ? "⌥⌘F searches from anywhere" : "⌥⌘V pins clipboard")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }
}

/// Top-right Claude logo: switches between the shelf and the Claude view. The ring
/// around it fills with the 5-hour usage, so it can be read without switching.
private struct ClaudeButton: View {
    let active: Bool
    let status: ClaudeSession.Status
    let fiveHourPercent: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? ClaudeLogo.orange.opacity(0.25) : Color.primary.opacity(0.1))
                if let percent = fiveHourPercent {
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(percent, 100) / 100))
                        .stroke(ClaudeLogo.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 22, height: 22)
                }
                ClaudeMarkView(status: status, size: fiveHourPercent == nil ? 14 : 11)
            }
            .frame(width: 30, height: 30)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(active ? ClaudeLogo.orange : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var helpText: String {
        var text = active ? "Back to the shelf" : "Claude sessions and usage"
        if let percent = fiveHourPercent { text += "\n5-hour usage: \(Int(percent.rounded()))%" }
        return text
    }
}

private struct EmptyClaudeView: View {
    let sessionsEnabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            ClaudeMarkView(status: .idle, size: 22)
            Text(sessionsEnabled
                 ? "No Claude Code sessions running. Start one in the Claude app or with `claude` in a terminal."
                 : "Session cards are off in Settings → Claude Code.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandMetrics.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}

private struct IconButton: View {
    @Environment(\.islandAccent) private var accent
    let systemName: String
    let help: String
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(highlighted ? accent : Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DropZoneView: View {
    @Environment(\.islandAccent) private var accent
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(accent)
            Text("Drop to pin on Shelf")
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandMetrics.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        )
    }
}

/// The search box in the header.
private struct SearchField: View {
    @Binding var text: String
    let focusToken: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search the shelf", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onEscape)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.1)))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: focusToken) { _ in DispatchQueue.main.async { focused = true } }
    }
}

private struct NoMatchesView: View {
    let query: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("No matches for “\(query)”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandMetrics.cardHeight)
    }
}

private struct EmptyShelfView: View {
    let filter: ShelfFilter

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(filter == .recent ? "Things you copy show up here." : "Nothing here yet. Drop a screenshot, file or text.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandMetrics.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}

/// Horizontally scrolling row of cards. Edges fade and arrow buttons appear
/// when there are more cards off to that side.
private struct CardStrip<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private let step = IslandMetrics.cardWidth + IslandMetrics.cardSpacing
    private let fade: CGFloat = 36

    private var canScrollLeft: Bool { offset < -1 }
    private var canScrollRight: Bool { contentWidth + offset > viewportWidth + 1 }
    private var firstVisible: Int { max(0, Int((-offset / step).rounded())) }
    private var perPage: Int { max(1, Int(viewportWidth / step)) }
    private var hiddenOnRight: Int {
        let lastFullyVisible = Int(((viewportWidth - offset) / step).rounded(.down))
        return max(0, items.count - lastFullyVisible)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: IslandMetrics.cardSpacing) {
                    ForEach(items) { item in
                        card(item).id(item.id)
                    }
                }
                .padding(.horizontal, 1)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: StripGeometryKey.self,
                                           value: CGSize(width: geo.frame(in: .named("strip")).minX,
                                                         height: geo.size.width))
                })
            }
            .coordinateSpace(name: "strip")
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { viewportWidth = geo.size.width }
                    .onChange(of: geo.size.width) { viewportWidth = $0 }
            })
            .onPreferenceChange(StripGeometryKey.self) { value in
                offset = value.width
                contentWidth = value.height
            }
            .mask(edgeFade)
            .overlay(alignment: .leading) {
                if canScrollLeft {
                    arrow("chevron.left", label: nil) { scroll(proxy, to: firstVisible - perPage) }
                }
            }
            .overlay(alignment: .trailing) {
                if canScrollRight {
                    arrow("chevron.right", label: hiddenOnRight > 0 ? "+\(hiddenOnRight)" : nil) {
                        scroll(proxy, to: firstVisible + perPage)
                    }
                }
            }
            .animation(.easeOut(duration: 0.15), value: canScrollLeft)
            .animation(.easeOut(duration: 0.15), value: canScrollRight)
        }
        .frame(height: IslandMetrics.cardHeight)
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(canScrollLeft ? 0 : 1), .black],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(canScrollRight ? 0 : 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
        }
    }

    private func arrow(_ systemName: String, label: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let label {
                    Text(label).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                }
                Image(systemName: systemName).font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, label == nil ? 0 : 7)
            .frame(minWidth: 24, minHeight: 24)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }

    private func scroll(_ proxy: ScrollViewProxy, to index: Int) {
        guard !items.isEmpty else { return }
        let target = min(max(0, index), items.count - 1)
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(items[target].id, anchor: .leading)
        }
    }
}

/// Vertically scrolling two-column grid, for the side panel.
private struct CardGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    private let columns = [GridItem(.adaptive(minimum: IslandMetrics.cardWidth), spacing: IslandMetrics.cardSpacing)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: columns, spacing: IslandMetrics.cardSpacing) {
                ForEach(items) { card($0) }
            }
            .padding(.vertical, 1)
        }
    }
}

/// width = scroll offset (minX of the content), height = content width.
private struct StripGeometryKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
