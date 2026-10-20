import AppKit
import SwiftUI

struct ExpandedShelfView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var store: ShelfStore
    @ObservedObject var settings: AppSettings
    let actions: IslandActions

    private var visibleItems: [ShelfItem] {
        switch model.filter {
        case .all: return store.pinned
        case .images: return store.pinned.filter { $0.kind == .image }
        case .text: return store.pinned.filter { $0.kind == .text }
        case .files: return store.pinned.filter { $0.kind == .file }
        case .recent: return store.recent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.isDropTargeted {
                DropZoneView()
            } else if visibleItems.isEmpty {
                EmptyShelfView(filter: model.filter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(visibleItems) { item in
                            ItemCardView(item: item, store: store, settings: settings)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(height: IslandMetrics.cardHeight)
            }

            footer
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Shelf")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(store.pinned.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }

            Spacer(minLength: 8)

            Picker("Filter", selection: $model.filter) {
                ForEach(ShelfFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 330)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                IconButton(systemName: model.isPinned ? "pin.fill" : "pin",
                           help: model.isPinned ? "Let the island close" : "Keep the island open (⌥Space)",
                           highlighted: model.isPinned,
                           action: actions.togglePin)
                IconButton(systemName: "gearshape", help: "Settings", highlighted: false, action: actions.openSettings)
            }
        }
        .frame(height: 30)
    }

    private var footer: some View {
        HStack {
            Text("Drag in to pin · drag out to use · double-click to open")
            Spacer()
            Text("⌥⌘V pins clipboard")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

private struct IconButton: View {
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
                    .fill(highlighted ? Color.accentColor : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct DropZoneView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Drop to pin on Shelf")
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandMetrics.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        )
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
                .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }
}
