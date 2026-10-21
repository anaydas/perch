import AppKit
import SwiftUI

/// The collapsed island, drawn for the current style and edge.
struct CollapsedIslandView: View {
    let layout: IslandLayout
    let items: [ShelfItem]
    @ObservedObject var store: ShelfStore
    let sessions: [ClaudeSession]
    let flashToken: Int
    @State private var bump = false

    var body: some View {
        content
            .scaleEffect(bump ? 1.12 : 1)
            .onChange(of: flashToken) { _ in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.4)) { bump = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { bump = false }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch layout.style {
        case .orb:
            OrbContent(count: items.count, sessions: sessions)
        case .notch, .floating:
            if layout.isVertical {
                VerticalPillContent(items: items, store: store, sessions: sessions)
            } else {
                HorizontalPillContent(notchGap: layout.notchGap, items: items, store: store, sessions: sessions)
            }
        }
    }
}

/// Recent items peeking out on the left, the count on the right, and an empty gap
/// where the hardware notch is (if any).
private struct HorizontalPillContent: View {
    let notchGap: CGFloat
    let items: [ShelfItem]
    @ObservedObject var store: ShelfStore
    let sessions: [ClaudeSession]

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: -6) {
                if items.isEmpty {
                    Image(systemName: "tray")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(items.prefix(3))) { item in
                    MiniThumb(item: item, store: store)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchGap)

            HStack(spacing: 5) {
                ClaudeIndicator(sessions: sessions)
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }
}

/// The same pieces stacked, for the left and right edges.
private struct VerticalPillContent: View {
    let items: [ShelfItem]
    @ObservedObject var store: ShelfStore
    let sessions: [ClaudeSession]

    var body: some View {
        VStack(spacing: 6) {
            if let item = items.first {
                MiniThumb(item: item, store: store)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if !items.isEmpty {
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            ClaudeIndicator(sessions: sessions)
        }
        .padding(.vertical, 10)
    }
}

/// Item count in a circle, with a small Claude dot when sessions are running.
private struct OrbContent: View {
    let count: Int
    let sessions: [ClaudeSession]

    var body: some View {
        ZStack {
            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: count > 99 ? 12 : 15, weight: .bold))
                    .monospacedDigit()
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if let top = sessions.first {
                ClaudeMarkView(status: top.status, size: 11)
                    .padding(5)
            }
        }
    }
}

private struct MiniThumb: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore

    var body: some View {
        Group {
            if item.kind == .image, let thumb = store.thumbnail(for: item) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(item.kind == .file ? Color.orange : Color.gray)
            }
        }
        .frame(width: 16, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black, lineWidth: 1.5))
    }
}
